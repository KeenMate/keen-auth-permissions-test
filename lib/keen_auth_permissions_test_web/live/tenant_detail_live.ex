defmodule KeenAuthPermissionsTestWeb.TenantDetailLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.Tenants
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler

  @impl true
  def mount(%{"tenant_id" => tenant_id_param}, session, socket) do
    user = session["current_user"]

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      tenant_id = String.to_integer(tenant_id_param)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(
          KeenAuthPermissionsTest.PubSub,
          "keen_auth:user:#{user.user_id}"
        )
      end

      ctx = build_context(user)

      {:ok,
       socket
       |> assign(
         page_title: "Tenant Detail",
         user: user,
         ctx: ctx,
         tenant_id: tenant_id,
         tenant: nil,
         members: [],
         groups: [],
         loading: true,
         error: nil,
         auth_blocked: false,
         auth_warning: false,
         auth_warning_message: "",
         # Tabs
         active_tab: :info,
         # Edit form
         editing: false,
         edit_form: %{},
         edit_saving: false,
         edit_error: nil,
         # Lazy load flags
         members_loaded: false,
         groups_loaded: false
       )
       |> load_tenant()}
    end
  end

  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_tenant/1)}
  end

  @impl true
  def handle_event("dismiss_auth_warning", _params, socket) do
    {:noreply, assign(socket, auth_warning: false, auth_warning_message: "")}
  end

  # ============================================================================
  # Tab switching
  # ============================================================================

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      case tab do
        :members ->
          if socket.assigns.members_loaded, do: socket, else: load_members(socket)

        :groups ->
          if socket.assigns.groups_loaded, do: socket, else: load_groups(socket)

        _ ->
          socket
      end

    {:noreply, assign(socket, active_tab: tab)}
  end

  # ============================================================================
  # Edit tenant
  # ============================================================================

  def handle_event("start_editing", _params, socket) do
    tenant = socket.assigns.tenant

    {:noreply,
     assign(socket,
       editing: true,
       edit_error: nil,
       edit_form: %{
         "title" => tenant.title,
         "code" => tenant.code,
         "is_removable" => to_string(tenant.is_removable),
         "is_assignable" => to_string(tenant.is_assignable),
         "owner_id" => ""
       }
     )}
  end

  def handle_event("cancel_editing", _params, socket) do
    {:noreply, assign(socket, editing: false, edit_error: nil)}
  end

  def handle_event("edit_form_change", params, socket) do
    {:noreply, assign(socket, edit_form: params)}
  end

  def handle_event("save_tenant", params, socket) do
    %{ctx: ctx, tenant_id: tenant_id} = socket.assigns

    title = String.trim(params["title"] || "")
    code = String.trim(params["code"] || "")
    owner_id = parse_integer(params["owner_id"])

    cond do
      title == "" ->
        {:noreply, assign(socket, edit_error: "Title is required")}

      code == "" ->
        {:noreply, assign(socket, edit_error: "Code is required")}

      true ->
        socket = assign(socket, edit_saving: true, edit_error: nil)

        case Tenants.update(
               ctx,
               tenant_id,
               title,
               code,
               params["is_removable"] == "true",
               params["is_assignable"] == "true",
               owner_id || 0
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(editing: false, edit_saving: false)
             |> put_flash(:info, "Tenant updated")
             |> load_tenant()}

          {:error, reason} ->
            Logger.error("Failed to update tenant", reason: inspect(reason))

            {:noreply,
             assign(socket,
               edit_saving: false,
               edit_error: "Failed to update: #{inspect(reason)}"
             )}
        end
    end
  end

  # ============================================================================
  # Delete tenant
  # ============================================================================

  def handle_event("delete_tenant", _params, socket) do
    %{ctx: ctx, tenant: tenant} = socket.assigns

    case Tenants.delete(ctx, tenant.uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tenant \"#{tenant.title}\" deleted")
         |> push_navigate(to: "/tenants")}

      {:error, reason} ->
        Logger.error("Failed to delete tenant", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Failed to delete tenant: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Data loading
  # ============================================================================

  defp load_tenant(socket) do
    %{tenant_id: tenant_id} = socket.assigns

    tenant =
      case Tenants.get_by_id(tenant_id) do
        {:ok, t} -> t
        _ -> nil
      end

    error = if is_nil(tenant), do: "Tenant not found", else: nil

    assign(socket,
      tenant: tenant,
      loading: false,
      error: error,
      page_title: if(tenant, do: tenant.title, else: "Tenant Detail")
    )
  end

  defp load_members(socket) do
    %{ctx: ctx, tenant_id: tenant_id} = socket.assigns

    members =
      case Tenants.list_members(ctx, tenant_id) do
        {:ok, m} -> m
        _ -> []
      end

    assign(socket, members: members, members_loaded: true)
  end

  defp load_groups(socket) do
    %{ctx: ctx, tenant_id: tenant_id} = socket.assigns

    groups =
      case Tenants.list_groups(ctx, tenant_id) do
        {:ok, g} -> g
        _ -> []
      end

    assign(socket, groups: groups, groups_loaded: true)
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp build_context(%User{} = user) do
    RequestContext.new(user)
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_event_listener auth_blocked={@auth_blocked} auth_warning={@auth_warning} auth_warning_message={@auth_warning_message} />
    <.admin_layout current_page={:tenants}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">
            <%= if @tenant, do: @tenant.title, else: "Tenant Detail" %>
          </h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li><a href="/tenants">Tenants</a></li>
              <li><%= if @tenant, do: @tenant.title, else: "..." %></li>
            </ul>
          </div>
        </div>

        <%= if @error do %>
          <div class="alert alert-error mb-6">
            <span><%= @error %></span>
          </div>
        <% end %>

        <%= if @loading do %>
          <div class="flex justify-center py-12">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% end %>

        <%= if @tenant && !@loading do %>
          <%!-- Tab Bar --%>
          <div role="tablist" class="tabs tabs-bordered mb-6">
            <button
              role="tab"
              class={"tab #{if @active_tab == :info, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="info"
            >
              Info
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :members, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="members"
            >
              Members (<%= length(@members) %>)
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :groups, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="groups"
            >
              Groups (<%= length(@groups) %>)
            </button>
          </div>

          <%!-- Tab Content --%>
          <%= case @active_tab do %>
            <% :info -> %>
              <.info_tab
                tenant={@tenant}
                editing={@editing}
                edit_form={@edit_form}
                edit_saving={@edit_saving}
                edit_error={@edit_error}
              />
            <% :members -> %>
              <.members_tab members={@members} />
            <% :groups -> %>
              <.groups_tab groups={@groups} />
          <% end %>
        <% end %>
    </.admin_layout>
    """
  end

  # ============================================================================
  # Info Tab
  # ============================================================================

  defp info_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">Tenant Info</h2>
          <div class="flex gap-2">
            <%= unless @editing do %>
              <button phx-click="start_editing" class="btn btn-sm btn-outline">Edit</button>
              <%= if @tenant.is_removable do %>
                <button
                  phx-click="delete_tenant"
                  data-confirm="Are you sure you want to delete this tenant? This action cannot be undone."
                  class="btn btn-sm btn-error btn-outline"
                >
                  Delete
                </button>
              <% end %>
            <% end %>
          </div>
        </div>

        <%= if @editing do %>
          <.edit_form
            edit_form={@edit_form}
            edit_saving={@edit_saving}
            edit_error={@edit_error}
          />
        <% else %>
          <.info_table tenant={@tenant} />
        <% end %>
      </div>
    </div>
    """
  end

  defp info_table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="table">
        <tbody>
          <tr>
            <th class="w-48">Tenant ID</th>
            <td><%= @tenant.tenant_id %></td>
          </tr>
          <tr>
            <th>Title</th>
            <td><%= @tenant.title %></td>
          </tr>
          <tr>
            <th>Code</th>
            <td><code class="text-sm"><%= @tenant.code %></code></td>
          </tr>
          <tr>
            <th>UUID</th>
            <td><code class="text-sm"><%= @tenant.uuid %></code></td>
          </tr>
          <tr>
            <th>Removable</th>
            <td>
              <%= if @tenant.is_removable do %>
                <span class="badge badge-success">Yes</span>
              <% else %>
                <span class="badge badge-ghost">No</span>
              <% end %>
            </td>
          </tr>
          <tr>
            <th>Assignable</th>
            <td>
              <%= if @tenant.is_assignable do %>
                <span class="badge badge-success">Yes</span>
              <% else %>
                <span class="badge badge-ghost">No</span>
              <% end %>
            </td>
          </tr>
          <tr>
            <th>Created At</th>
            <td><%= format_datetime(@tenant.created_at) %></td>
          </tr>
          <tr>
            <th>Updated At</th>
            <td><%= format_datetime(@tenant.updated_at) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp edit_form(assigns) do
    ~H"""
    <%= if @edit_error do %>
      <div class="alert alert-error mb-4">
        <span><%= @edit_error %></span>
      </div>
    <% end %>

    <form phx-submit="save_tenant" phx-change="edit_form_change">
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div class="form-control">
          <label class="label">
            <span class="label-text">Title</span>
          </label>
          <input
            type="text"
            name="title"
            value={@edit_form["title"]}
            class="input input-bordered"
            required
          />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text">Code</span>
          </label>
          <input
            type="text"
            name="code"
            value={@edit_form["code"]}
            class="input input-bordered"
            required
          />
        </div>

        <div class="form-control">
          <label class="label">
            <span class="label-text">Owner ID (leave empty to keep current)</span>
          </label>
          <input
            type="text"
            name="owner_id"
            value={@edit_form["owner_id"]}
            placeholder="User ID"
            class="input input-bordered"
          />
        </div>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-4 gap-3 mt-3">
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Removable</span>
            <input type="hidden" name="is_removable" value="false" />
            <input
              type="checkbox"
              name="is_removable"
              value="true"
              checked={@edit_form["is_removable"] == "true"}
              class="checkbox"
            />
          </label>
        </div>

        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Assignable</span>
            <input type="hidden" name="is_assignable" value="false" />
            <input
              type="checkbox"
              name="is_assignable"
              value="true"
              checked={@edit_form["is_assignable"] == "true"}
              class="checkbox"
            />
          </label>
        </div>
      </div>

      <div class="flex gap-2 mt-4">
        <button type="button" phx-click="cancel_editing" class="btn btn-ghost">Cancel</button>
        <button type="submit" class={"btn btn-primary #{if @edit_saving, do: "loading"}"} disabled={@edit_saving}>
          Save
        </button>
      </div>
    </form>
    """
  end

  # ============================================================================
  # Members Tab
  # ============================================================================

  defp members_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Tenant Members (<%= length(@members) %>)</h2>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>User ID</th>
                <th>Display Name</th>
                <th>Code</th>
                <th>Groups</th>
              </tr>
            </thead>
            <tbody>
              <%= for member <- @members do %>
                <tr>
                  <td><%= member.user_id %></td>
                  <td>
                    <a href={"/users/#{member.user_id}"} class="link link-primary">
                      <%= member.user_display_name %>
                    </a>
                  </td>
                  <td><code class="text-sm"><%= member.user_code %></code></td>
                  <td>
                    <%= if member.user_tenant_groups && member.user_tenant_groups != "" do %>
                      <span class="text-sm"><%= member.user_tenant_groups %></span>
                    <% else %>
                      <span class="text-base-content/30">-</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@members) do %>
                <tr>
                  <td colspan="4" class="text-center text-base-content/50 py-8">
                    No members in this tenant
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Groups Tab
  # ============================================================================

  defp groups_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Tenant Groups (<%= length(@groups) %>)</h2>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>ID</th>
                <th>Title</th>
                <th>Code</th>
                <th>Type</th>
                <th>Members</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <%= for group <- @groups do %>
                <tr>
                  <td><%= group.user_group_id %></td>
                  <td>
                    <a href={"/groups/#{group.user_group_id}"} class="link link-primary">
                      <%= group.group_title %>
                    </a>
                  </td>
                  <td><code class="text-sm"><%= group.group_code %></code></td>
                  <td>
                    <span class={"badge #{type_badge(group)}"}>
                      <%= group_type_label(group) %>
                    </span>
                  </td>
                  <td><%= group.members_count %></td>
                  <td>
                    <%= if group.is_active do %>
                      <span class="badge badge-success badge-sm">Active</span>
                    <% else %>
                      <span class="badge badge-error badge-sm">Disabled</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@groups) do %>
                <tr>
                  <td colspan="6" class="text-center text-base-content/50 py-8">
                    No groups in this tenant
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp type_badge(%{is_external: true}), do: "badge-warning"
  defp type_badge(_), do: "badge-primary"

  defp group_type_label(%{is_external: true}), do: "external"
  defp group_type_label(_), do: "internal"

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
