defmodule KeenAuthPermissionsTestWeb.PermSetDetailLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.PermSets
  alias KeenAuthPermissions.Permissions
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler

  @default_tenant_id 1

  @impl true
  def mount(%{"perm_set_id" => perm_set_id_param}, session, socket) do
    user = session["current_user"]

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      perm_set_id = String.to_integer(perm_set_id_param)

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
         page_title: "Permission Set Detail",
         user: user,
         ctx: ctx,
         perm_set_id: perm_set_id,
         perm_set: nil,
         current_permissions: [],
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
         # Add permission
         add_perm_code: "",
         available_permissions: [],
         perm_add_error: nil
       )
       |> load_perm_set()}
    end
  end

  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_perm_set/1)}
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
        :permissions ->
          if Enum.empty?(socket.assigns.available_permissions) do
            load_available_permissions(socket)
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, assign(socket, active_tab: tab)}
  end

  # ============================================================================
  # Edit perm set
  # ============================================================================

  def handle_event("start_editing", _params, socket) do
    ps = socket.assigns.perm_set

    {:noreply,
     assign(socket,
       editing: true,
       edit_error: nil,
       edit_form: %{
         "title" => ps.title,
         "is_assignable" => to_string(ps.is_assignable)
       }
     )}
  end

  def handle_event("cancel_editing", _params, socket) do
    {:noreply, assign(socket, editing: false, edit_error: nil)}
  end

  def handle_event("edit_form_change", params, socket) do
    {:noreply, assign(socket, edit_form: params)}
  end

  def handle_event("save_perm_set", params, socket) do
    %{ctx: ctx, perm_set_id: perm_set_id} = socket.assigns

    title = String.trim(params["title"] || "")

    if title == "" do
      {:noreply, assign(socket, edit_error: "Title is required")}
    else
      socket = assign(socket, edit_saving: true, edit_error: nil)

      case PermSets.update(
             ctx,
             perm_set_id,
             title,
             params["is_assignable"] == "true",
             @default_tenant_id
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(editing: false, edit_saving: false)
           |> put_flash(:info, "Permission set updated")
           |> load_perm_set()}

        {:error, reason} ->
          Logger.error("Failed to update permission set", reason: inspect(reason))

          {:noreply,
           assign(socket,
             edit_saving: false,
             edit_error: "Failed to update: #{inspect(reason)}"
           )}
      end
    end
  end

  # ============================================================================
  # Delete perm set
  # ============================================================================

  # Note: PermSets facade doesn't have a delete function yet.
  # The delete button is hidden for system perm sets.
  # If a delete function is added to the facade, uncomment this handler.
  # For now, we redirect to the list page with a message.

  # def handle_event("delete_perm_set", _params, socket) do
  #   ...
  # end

  # ============================================================================
  # Manage permissions
  # ============================================================================

  def handle_event("add_permission", params, socket) do
    %{ctx: ctx, perm_set_id: perm_set_id} = socket.assigns

    perm_code = String.trim(params["perm_code"] || "")

    if perm_code == "" do
      {:noreply, assign(socket, perm_add_error: "Permission code is required")}
    else
      case PermSets.add_permissions(ctx, perm_set_id, [perm_code], @default_tenant_id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(add_perm_code: "", perm_add_error: nil)
           |> put_flash(:info, "Permission added")
           |> reload_permissions()}

        {:error, reason} ->
          Logger.error("Failed to add permission", reason: inspect(reason))

          {:noreply,
           assign(socket, perm_add_error: "Failed to add permission: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("remove_permission", %{"code" => perm_code}, socket) do
    %{ctx: ctx, perm_set_id: perm_set_id} = socket.assigns

    case PermSets.delete_permissions(ctx, perm_set_id, [perm_code], @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Permission removed")
         |> reload_permissions()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to remove permission: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Data loading
  # ============================================================================

  defp load_perm_set(socket) do
    %{ctx: ctx, perm_set_id: perm_set_id} = socket.assigns

    # Get perm set details from the list (which includes permissions)
    {perm_set, current_permissions} =
      case PermSets.list(ctx, @default_tenant_id) do
        {:ok, sets} ->
          case Enum.find(sets, &(&1.perm_set_id == perm_set_id)) do
            %{permissions: perms} = ps when is_list(perms) -> {ps, perms}
            %{permissions: perms} = ps when is_map(perms) -> {ps, Map.values(perms)}
            ps -> {ps, []}
          end

        _ ->
          {nil, []}
      end

    error = if is_nil(perm_set), do: "Permission set not found", else: nil

    assign(socket,
      perm_set: perm_set,
      current_permissions: current_permissions,
      loading: false,
      error: error,
      page_title: if(perm_set, do: perm_set.title, else: "Permission Set Detail")
    )
  end

  defp reload_permissions(socket) do
    %{ctx: ctx, perm_set_id: perm_set_id} = socket.assigns

    current_permissions =
      case PermSets.list(ctx, @default_tenant_id) do
        {:ok, sets} ->
          case Enum.find(sets, &(&1.perm_set_id == perm_set_id)) do
            %{permissions: perms} when is_list(perms) -> perms
            %{permissions: perms} when is_map(perms) -> Map.values(perms)
            _ -> []
          end

        _ ->
          []
      end

    assign(socket, current_permissions: current_permissions)
  end

  defp load_available_permissions(socket) do
    %{ctx: ctx} = socket.assigns

    available =
      case Permissions.search(ctx, nil, true, nil, 1, 500, @default_tenant_id) do
        {:ok, perms} -> perms
        _ -> []
      end

    assign(socket, available_permissions: available)
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
    <.admin_layout current_page={:perm_sets}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">
            <%= if @perm_set, do: @perm_set.title, else: "Permission Set Detail" %>
          </h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li><a href="/perm-sets">Permission Sets</a></li>
              <li><%= if @perm_set, do: @perm_set.title, else: "..." %></li>
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

        <%= if @perm_set && !@loading do %>
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
              class={"tab #{if @active_tab == :permissions, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="permissions"
            >
              Permissions (<%= length(@current_permissions) %>)
            </button>
          </div>

          <%!-- Tab Content --%>
          <%= case @active_tab do %>
            <% :info -> %>
              <.info_tab
                perm_set={@perm_set}
                editing={@editing}
                edit_form={@edit_form}
                edit_saving={@edit_saving}
                edit_error={@edit_error}
              />
            <% :permissions -> %>
              <.permissions_tab
                current_permissions={@current_permissions}
                available_permissions={@available_permissions}
                add_perm_code={@add_perm_code}
                perm_add_error={@perm_add_error}
              />
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
          <h2 class="card-title">Permission Set Info</h2>
          <%= unless @editing do %>
            <button phx-click="start_editing" class="btn btn-sm btn-outline">Edit</button>
          <% end %>
        </div>

        <%= if @editing do %>
          <.edit_form
            edit_form={@edit_form}
            edit_saving={@edit_saving}
            edit_error={@edit_error}
          />
        <% else %>
          <.info_table perm_set={@perm_set} />
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
            <th class="w-48">Perm Set ID</th>
            <td><%= @perm_set.perm_set_id %></td>
          </tr>
          <tr>
            <th>Title</th>
            <td><%= @perm_set.title %></td>
          </tr>
          <tr>
            <th>Code</th>
            <td><code class="text-sm"><%= @perm_set.code %></code></td>
          </tr>
          <tr>
            <th>Type</th>
            <td>
              <%= if @perm_set.is_system do %>
                <span class="badge badge-info">system</span>
              <% else %>
                <span class="badge badge-ghost">custom</span>
              <% end %>
            </td>
          </tr>
          <tr>
            <th>Assignable</th>
            <td>
              <%= if @perm_set.is_assignable do %>
                <span class="badge badge-success">Yes</span>
              <% else %>
                <span class="badge badge-ghost">No</span>
              <% end %>
            </td>
          </tr>
          <tr>
            <th>Source</th>
            <td>
              <%= if @perm_set.source do %>
                <span class="badge badge-outline"><%= @perm_set.source %></span>
              <% else %>
                <span class="text-base-content/30">-</span>
              <% end %>
            </td>
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

    <form phx-submit="save_perm_set" phx-change="edit_form_change">
      <div class="form-control mb-3">
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

      <div class="form-control mb-3">
        <label class="label cursor-pointer justify-start gap-3">
          <input type="hidden" name="is_assignable" value="false" />
          <input
            type="checkbox"
            name="is_assignable"
            value="true"
            checked={@edit_form["is_assignable"] == "true"}
            class="checkbox"
          />
          <span class="label-text">Assignable</span>
        </label>
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
  # Permissions Tab
  # ============================================================================

  defp permissions_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl mb-6">
      <div class="card-body">
        <h2 class="card-title mb-4">Add Permission</h2>

        <%= if @perm_add_error do %>
          <div class="alert alert-error mb-4">
            <span><%= @perm_add_error %></span>
          </div>
        <% end %>

        <form phx-submit="add_permission" class="flex gap-2">
          <input
            type="text"
            name="perm_code"
            value={@add_perm_code}
            placeholder="Permission code to add..."
            class="input input-bordered flex-1 max-w-md"
            list="available-perms"
            autocomplete="off"
          />
          <datalist id="available-perms">
            <%= for perm <- @available_permissions do %>
              <option value={perm.full_code}><%= perm.title %></option>
            <% end %>
          </datalist>
          <button type="submit" class="btn btn-primary">Add</button>
        </form>
      </div>
    </div>

    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Current Permissions (<%= length(@current_permissions) %>)</h2>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Code</th>
                <th>Title</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for perm <- @current_permissions do %>
                <% {perm_code, perm_title} = extract_perm_info(perm) %>
                <tr>
                  <td><code class="text-sm"><%= perm_code %></code></td>
                  <td><%= perm_title %></td>
                  <td>
                    <button
                      phx-click="remove_permission"
                      phx-value-code={perm_code}
                      data-confirm={"Remove permission #{perm_code} from this set?"}
                      class="btn btn-ghost btn-xs text-error"
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@current_permissions) do %>
                <tr>
                  <td colspan="3" class="text-center text-base-content/50 py-8">
                    No permissions assigned to this set
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

  defp extract_perm_info(%{"code" => code, "title" => title}), do: {code, title}
  defp extract_perm_info(%{"code" => code}), do: {code, ""}
  defp extract_perm_info(%{permission_code: code}), do: {code, ""}
  defp extract_perm_info(perm) when is_binary(perm), do: {perm, ""}
  defp extract_perm_info(perm), do: {inspect(perm), ""}
end
