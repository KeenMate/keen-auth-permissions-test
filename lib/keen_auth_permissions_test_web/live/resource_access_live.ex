defmodule KeenAuthPermissionsTestWeb.ResourceAccessLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.ResourceAccess
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler

  @default_tenant_id 1

  @impl true
  def mount(_params, session, socket) do
    user = session["current_user"]

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/login")}
    else
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
         page_title: "Resource Access",
         user: user,
         ctx: ctx,
         auth_blocked: false,
         auth_warning: false,
         auth_warning_message: "",
         # Resource selector
         resource_types: [],
         resource_type: "",
         resource_id: "",
         resource_loaded: false,
         # Tabs
         active_tab: :grants,
         # Grants tab
         grants: [],
         grants_loading: false,
         grants_error: nil,
         # Access Check tab
         check_user_id: "",
         check_flag: "",
         check_result: nil,
         check_error: nil,
         filter_ids: "",
         filter_flag: "",
         filter_result: nil,
         filter_error: nil,
         # My Flags tab
         flags: [],
         flags_loading: false,
         flags_loaded: false,
         # Matrix tab
         matrix: [],
         matrix_loading: false,
         matrix_loaded: false,
         # User Resources tab
         ur_user_id: "",
         ur_resource_type: "",
         ur_flag: "",
         user_resources: [],
         ur_loading: false,
         ur_error: nil,
         # Grant modal
         show_grant_modal: false,
         grant_form: %{"target_user_id" => "", "user_group_id" => "", "access_flags" => ""},
         grant_saving: false,
         grant_error: nil,
         # Deny modal
         show_deny_modal: false,
         deny_form: %{"target_user_id" => "", "access_flags" => ""},
         deny_saving: false,
         deny_error: nil,
         # Revoke modal
         show_revoke_modal: false,
         revoke_form: %{"target_user_id" => "", "user_group_id" => "", "access_flags" => ""},
         revoke_saving: false,
         revoke_error: nil
       )
       |> load_resource_types()}
    end
  end

  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    reload_fn = fn s ->
      if s.assigns.resource_loaded, do: load_grants(s), else: s
    end

    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, reload_fn)}
  end

  @impl true
  def handle_event("dismiss_auth_warning", _params, socket) do
    {:noreply, assign(socket, auth_warning: false, auth_warning_message: "")}
  end

  # ============================================================================
  # Resource Selector
  # ============================================================================

  def handle_event("selector_change", params, socket) do
    {:noreply,
     assign(socket,
       resource_type: params["resource_type"] || "",
       resource_id: params["resource_id"] || ""
     )}
  end

  def handle_event("load_resource", _params, socket) do
    resource_type = String.trim(socket.assigns.resource_type)
    resource_id_str = String.trim(socket.assigns.resource_id)

    cond do
      resource_type == "" ->
        {:noreply, put_flash(socket, :error, "Resource type is required")}

      parse_integer(resource_id_str) == nil ->
        {:noreply, put_flash(socket, :error, "Resource ID must be a valid number")}

      true ->
        {:noreply,
         socket
         |> assign(
           resource_loaded: true,
           active_tab: :grants,
           grants: [],
           grants_loading: true,
           grants_error: nil,
           # Reset tab data
           flags: [],
           flags_loaded: false,
           matrix: [],
           matrix_loaded: false,
           check_result: nil,
           check_error: nil,
           filter_result: nil,
           filter_error: nil,
           user_resources: [],
           ur_error: nil
         )
         |> load_grants()}
    end
  end

  # ============================================================================
  # Tab switching
  # ============================================================================

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)
    socket = assign(socket, active_tab: tab)

    socket =
      case tab do
        :flags ->
          if socket.assigns.flags_loaded, do: socket, else: load_flags(socket)

        :matrix ->
          if socket.assigns.matrix_loaded, do: socket, else: load_matrix(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # ============================================================================
  # Grants tab actions
  # ============================================================================

  def handle_event("revoke_all", _params, socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)

    case ResourceAccess.revoke_all(ctx, resource_type, resource_id, @default_tenant_id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "Revoked all access (#{count} entries removed)")
         |> reload_all_tabs()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke all: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Grant modal
  # ============================================================================

  def handle_event("open_grant_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_grant_modal: true,
       grant_form: %{"target_user_id" => "", "user_group_id" => "", "access_flags" => ""},
       grant_error: nil
     )}
  end

  def handle_event("close_grant_modal", _params, socket) do
    {:noreply, assign(socket, show_grant_modal: false, grant_error: nil)}
  end

  def handle_event("grant_form_change", params, socket) do
    {:noreply, assign(socket, grant_form: params)}
  end

  def handle_event("submit_grant", params, socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)

    target_user_id = parse_integer(params["target_user_id"])
    user_group_id = parse_integer(params["user_group_id"])
    flags_str = String.trim(params["access_flags"] || "")

    cond do
      target_user_id == nil and user_group_id == nil ->
        {:noreply, assign(socket, grant_error: "Either User ID or Group ID is required")}

      flags_str == "" ->
        {:noreply, assign(socket, grant_error: "Access flags are required")}

      true ->
        access_flags = parse_flags(flags_str)
        socket = assign(socket, grant_saving: true, grant_error: nil)

        case ResourceAccess.grant(
               ctx,
               resource_type,
               resource_id,
               target_user_id,
               user_group_id,
               access_flags,
               @default_tenant_id
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(show_grant_modal: false, grant_saving: false)
             |> put_flash(:info, "Access granted")
             |> reload_all_tabs()}

          {:error, reason} ->
            Logger.error("Failed to grant access", reason: inspect(reason))

            {:noreply,
             assign(socket,
               grant_saving: false,
               grant_error: "Failed to grant: #{inspect(reason)}"
             )}
        end
    end
  end

  # ============================================================================
  # Deny modal
  # ============================================================================

  def handle_event("open_deny_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_deny_modal: true,
       deny_form: %{"target_user_id" => "", "access_flags" => ""},
       deny_error: nil
     )}
  end

  def handle_event("close_deny_modal", _params, socket) do
    {:noreply, assign(socket, show_deny_modal: false, deny_error: nil)}
  end

  def handle_event("deny_form_change", params, socket) do
    {:noreply, assign(socket, deny_form: params)}
  end

  def handle_event("submit_deny", params, socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)

    target_user_id = parse_integer(params["target_user_id"])
    flags_str = String.trim(params["access_flags"] || "")

    cond do
      target_user_id == nil ->
        {:noreply, assign(socket, deny_error: "User ID is required")}

      flags_str == "" ->
        {:noreply, assign(socket, deny_error: "Access flags are required")}

      true ->
        access_flags = parse_flags(flags_str)
        socket = assign(socket, deny_saving: true, deny_error: nil)

        case ResourceAccess.deny(
               ctx,
               resource_type,
               resource_id,
               target_user_id,
               access_flags,
               @default_tenant_id
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(show_deny_modal: false, deny_saving: false)
             |> put_flash(:info, "Access denied")
             |> reload_all_tabs()}

          {:error, reason} ->
            Logger.error("Failed to deny access", reason: inspect(reason))

            {:noreply,
             assign(socket,
               deny_saving: false,
               deny_error: "Failed to deny: #{inspect(reason)}"
             )}
        end
    end
  end

  # ============================================================================
  # Revoke modal
  # ============================================================================

  def handle_event("open_revoke_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_revoke_modal: true,
       revoke_form: %{"target_user_id" => "", "user_group_id" => "", "access_flags" => ""},
       revoke_error: nil
     )}
  end

  def handle_event("close_revoke_modal", _params, socket) do
    {:noreply, assign(socket, show_revoke_modal: false, revoke_error: nil)}
  end

  def handle_event("revoke_form_change", params, socket) do
    {:noreply, assign(socket, revoke_form: params)}
  end

  def handle_event("submit_revoke", params, socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)

    target_user_id = parse_integer(params["target_user_id"])
    user_group_id = parse_integer(params["user_group_id"])
    flags_str = String.trim(params["access_flags"] || "")

    cond do
      target_user_id == nil and user_group_id == nil ->
        {:noreply, assign(socket, revoke_error: "Either User ID or Group ID is required")}

      flags_str == "" ->
        {:noreply, assign(socket, revoke_error: "Access flags are required")}

      true ->
        access_flags = parse_flags(flags_str)
        socket = assign(socket, revoke_saving: true, revoke_error: nil)

        case ResourceAccess.revoke(
               ctx,
               resource_type,
               resource_id,
               target_user_id,
               user_group_id,
               access_flags,
               @default_tenant_id
             ) do
          {:ok, count} ->
            {:noreply,
             socket
             |> assign(show_revoke_modal: false, revoke_saving: false)
             |> put_flash(:info, "Revoked #{count} entries")
             |> reload_all_tabs()}

          {:error, reason} ->
            Logger.error("Failed to revoke access", reason: inspect(reason))

            {:noreply,
             assign(socket,
               revoke_saving: false,
               revoke_error: "Failed to revoke: #{inspect(reason)}"
             )}
        end
    end
  end

  # ============================================================================
  # Access Check tab
  # ============================================================================

  def handle_event("check_access_change", params, socket) do
    {:noreply,
     assign(socket,
       check_user_id: params["check_user_id"] || socket.assigns.check_user_id,
       check_flag: params["check_flag"] || socket.assigns.check_flag
     )}
  end

  def handle_event("check_access", params, socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)

    check_user_id = parse_integer(params["check_user_id"])
    flag = String.trim(params["check_flag"] || "")

    cond do
      check_user_id == nil ->
        {:noreply, assign(socket, check_error: "User ID is required")}

      flag == "" ->
        {:noreply, assign(socket, check_error: "Access flag is required")}

      true ->
        # Build a context for the target user to check their access
        target_ctx = build_context_for_user_id(ctx, check_user_id)

        case ResourceAccess.has_access?(target_ctx, resource_type, resource_id, flag, @default_tenant_id) do
          {:ok, result} ->
            {:noreply, assign(socket, check_result: result, check_error: nil)}

          {:error, reason} ->
            {:noreply,
             assign(socket, check_result: nil, check_error: "Error: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("filter_change", params, socket) do
    {:noreply,
     assign(socket,
       filter_ids: params["filter_ids"] || socket.assigns.filter_ids,
       filter_flag: params["filter_flag"] || socket.assigns.filter_flag
     )}
  end

  def handle_event("filter_accessible", params, socket) do
    %{ctx: ctx, resource_type: resource_type} = socket.assigns

    ids_str = String.trim(params["filter_ids"] || "")
    flag = String.trim(params["filter_flag"] || "")

    cond do
      ids_str == "" ->
        {:noreply, assign(socket, filter_error: "Resource IDs are required")}

      flag == "" ->
        {:noreply, assign(socket, filter_error: "Access flag is required")}

      true ->
        resource_ids =
          ids_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&parse_integer/1)
          |> Enum.reject(&is_nil/1)

        if Enum.empty?(resource_ids) do
          {:noreply, assign(socket, filter_error: "No valid resource IDs found")}
        else
          case ResourceAccess.filter_accessible(ctx, resource_type, resource_ids, flag, @default_tenant_id) do
            {:ok, result} ->
              {:noreply, assign(socket, filter_result: result, filter_error: nil)}

            {:error, reason} ->
              {:noreply,
               assign(socket, filter_result: nil, filter_error: "Error: #{inspect(reason)}")}
          end
        end
    end
  end

  # ============================================================================
  # User Resources tab
  # ============================================================================

  def handle_event("ur_change", params, socket) do
    {:noreply,
     assign(socket,
       ur_user_id: params["ur_user_id"] || socket.assigns.ur_user_id,
       ur_resource_type: params["ur_resource_type"] || socket.assigns.ur_resource_type,
       ur_flag: params["ur_flag"] || socket.assigns.ur_flag
     )}
  end

  def handle_event("load_user_resources", params, socket) do
    %{ctx: ctx} = socket.assigns

    target_user_id = parse_integer(params["ur_user_id"])
    resource_type = String.trim(params["ur_resource_type"] || "")
    flag = blank_to_nil(params["ur_flag"])

    cond do
      target_user_id == nil ->
        {:noreply, assign(socket, ur_error: "User ID is required")}

      resource_type == "" ->
        {:noreply, assign(socket, ur_error: "Resource type is required")}

      true ->
        socket = assign(socket, ur_loading: true, ur_error: nil)

        case ResourceAccess.get_user_resources(
               ctx,
               target_user_id,
               resource_type,
               flag,
               @default_tenant_id
             ) do
          {:ok, resources} ->
            {:noreply,
             assign(socket, user_resources: resources, ur_loading: false, ur_error: nil)}

          {:error, reason} ->
            Logger.error("Failed to load user resources", reason: inspect(reason))

            {:noreply,
             assign(socket,
               user_resources: [],
               ur_loading: false,
               ur_error: "Failed to load: #{inspect(reason)}"
             )}
        end
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp load_resource_types(socket) do
    case ResourceAccess.list_resource_types() do
      {:ok, resource_types} ->
        assign(socket, resource_types: resource_types)

      {:error, _reason} ->
        assign(socket, resource_types: [])
    end
  end

  defp load_grants(socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)

    case ResourceAccess.get_grants(ctx, resource_type, resource_id, @default_tenant_id) do
      {:ok, grants} ->
        assign(socket, grants: grants, grants_loading: false, grants_error: nil)

      {:error, reason} ->
        Logger.error("Failed to load grants", reason: inspect(reason))

        assign(socket,
          grants: [],
          grants_loading: false,
          grants_error: "Failed to load grants: #{inspect(reason)}"
        )
    end
  end

  defp load_flags(socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)
    socket = assign(socket, flags_loading: true)

    case ResourceAccess.get_flags(ctx, resource_type, resource_id, @default_tenant_id) do
      {:ok, flags} ->
        assign(socket, flags: flags, flags_loading: false, flags_loaded: true)

      {:error, reason} ->
        Logger.error("Failed to load flags", reason: inspect(reason))
        assign(socket, flags: [], flags_loading: false, flags_loaded: true)
    end
  end

  defp load_matrix(socket) do
    %{ctx: ctx, resource_type: resource_type, resource_id: resource_id_str} = socket.assigns
    resource_id = parse_integer(resource_id_str)
    socket = assign(socket, matrix_loading: true)

    case ResourceAccess.get_matrix(ctx, resource_type, resource_id, @default_tenant_id) do
      {:ok, matrix} ->
        assign(socket, matrix: matrix, matrix_loading: false, matrix_loaded: true)

      {:error, reason} ->
        Logger.error("Failed to load matrix", reason: inspect(reason))
        assign(socket, matrix: [], matrix_loading: false, matrix_loaded: true)
    end
  end

  defp reload_all_tabs(socket) do
    socket
    |> assign(
      grants_loading: true,
      flags_loaded: false,
      matrix_loaded: false
    )
    |> load_grants()
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_flags(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp build_context(%User{} = user) do
    RequestContext.new(user)
  end

  defp build_context_for_user_id(%RequestContext{} = base_ctx, target_user_id) do
    # Create a minimal context with the target user's ID for access checking
    %RequestContext{
      base_ctx
      | user: %User{base_ctx.user | user_id: target_user_id}
    }
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_event_listener auth_blocked={@auth_blocked} auth_warning={@auth_warning} auth_warning_message={@auth_warning_message} />
    <.admin_layout current_page={:resource_access}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Resource Access</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Resource Access</li>
            </ul>
          </div>
        </div>

        <%!-- Resource Selector --%>
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title mb-4">Select Resource</h2>
            <form phx-submit="load_resource" phx-change="selector_change">
              <div class="flex items-end gap-4">
                <div class="form-control flex-1">
                  <label class="label">
                    <span class="label-text">Resource Type</span>
                  </label>
                  <select name="resource_type" class="select select-bordered" required>
                    <option value="" disabled selected={@resource_type == ""}>
                      Select resource type
                    </option>
                    <%= for rt <- @resource_types do %>
                      <option value={rt.code} selected={@resource_type == rt.code}>
                        <%= rt.full_title %> (<%= rt.code %>)
                      </option>
                    <% end %>
                  </select>
                </div>
                <div class="form-control flex-1">
                  <label class="label">
                    <span class="label-text">Resource ID</span>
                  </label>
                  <input
                    type="number"
                    name="resource_id"
                    value={@resource_id}
                    placeholder="e.g. 1"
                    class="input input-bordered"
                    required
                  />
                </div>
                <button type="submit" class="btn btn-primary">Load</button>
              </div>
            </form>
          </div>
        </div>

        <%= if @resource_loaded do %>
          <div class="mb-2">
            <span class="badge badge-lg badge-primary">
              <%= @resource_type %> / <%= @resource_id %>
            </span>
          </div>

          <%!-- Tab Bar --%>
          <div role="tablist" class="tabs tabs-bordered mb-6">
            <button
              role="tab"
              class={"tab #{if @active_tab == :grants, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="grants"
            >
              Grants (<%= length(@grants) %>)
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :access_check, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="access_check"
            >
              Access Check
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :flags, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="flags"
            >
              My Flags
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :matrix, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="matrix"
            >
              Matrix
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :user_resources, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="user_resources"
            >
              User Resources
            </button>
          </div>

          <%!-- Tab Content --%>
          <%= case @active_tab do %>
            <% :grants -> %>
              <.grants_tab grants={@grants} loading={@grants_loading} error={@grants_error} />
            <% :access_check -> %>
              <.access_check_tab
                check_user_id={@check_user_id}
                check_flag={@check_flag}
                check_result={@check_result}
                check_error={@check_error}
                filter_ids={@filter_ids}
                filter_flag={@filter_flag}
                filter_result={@filter_result}
                filter_error={@filter_error}
              />
            <% :flags -> %>
              <.flags_tab flags={@flags} loading={@flags_loading} />
            <% :matrix -> %>
              <.matrix_tab matrix={@matrix} loading={@matrix_loading} />
            <% :user_resources -> %>
              <.user_resources_tab
                ur_user_id={@ur_user_id}
                ur_resource_type={@ur_resource_type}
                ur_flag={@ur_flag}
                user_resources={@user_resources}
                loading={@ur_loading}
                error={@ur_error}
              />
          <% end %>
        <% end %>

    <%!-- Grant Modal --%>
    <%= if @show_grant_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Grant Access</h3>

          <%= if @grant_error do %>
            <div class="alert alert-error mb-4">
              <span><%= @grant_error %></span>
            </div>
          <% end %>

          <form phx-submit="submit_grant" phx-change="grant_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">User ID</th>
                  <td>
                    <input
                      type="text"
                      name="target_user_id"
                      value={@grant_form["target_user_id"]}
                      placeholder="User ID (or leave empty for group)"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Group ID</th>
                  <td>
                    <input
                      type="text"
                      name="user_group_id"
                      value={@grant_form["user_group_id"]}
                      placeholder="Group ID (or leave empty for user)"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Access Flags</th>
                  <td>
                    <input
                      type="text"
                      name="access_flags"
                      value={@grant_form["access_flags"]}
                      placeholder="read, write, delete"
                      class="input input-bordered w-full"
                      required
                    />
                    <label class="label">
                      <span class="label-text-alt">Comma-separated list of flags</span>
                    </label>
                  </td>
                </tr>
              </tbody>
            </table>

            <div class="modal-action">
              <button type="button" phx-click="close_grant_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-primary #{if @grant_saving, do: "loading"}"}
                disabled={@grant_saving}
              >
                Grant
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_grant_modal"></div>
      </div>
    <% end %>

    <%!-- Deny Modal --%>
    <%= if @show_deny_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Deny Access</h3>

          <%= if @deny_error do %>
            <div class="alert alert-error mb-4">
              <span><%= @deny_error %></span>
            </div>
          <% end %>

          <form phx-submit="submit_deny" phx-change="deny_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">User ID</th>
                  <td>
                    <input
                      type="text"
                      name="target_user_id"
                      value={@deny_form["target_user_id"]}
                      placeholder="User ID to deny"
                      class="input input-bordered w-full"
                      required
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Access Flags</th>
                  <td>
                    <input
                      type="text"
                      name="access_flags"
                      value={@deny_form["access_flags"]}
                      placeholder="read, write, delete"
                      class="input input-bordered w-full"
                      required
                    />
                    <label class="label">
                      <span class="label-text-alt">Comma-separated list of flags to deny</span>
                    </label>
                  </td>
                </tr>
              </tbody>
            </table>

            <div class="modal-action">
              <button type="button" phx-click="close_deny_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-error #{if @deny_saving, do: "loading"}"}
                disabled={@deny_saving}
              >
                Deny
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_deny_modal"></div>
      </div>
    <% end %>

    <%!-- Revoke Modal --%>
    <%= if @show_revoke_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Revoke Access</h3>

          <%= if @revoke_error do %>
            <div class="alert alert-error mb-4">
              <span><%= @revoke_error %></span>
            </div>
          <% end %>

          <form phx-submit="submit_revoke" phx-change="revoke_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">User ID</th>
                  <td>
                    <input
                      type="text"
                      name="target_user_id"
                      value={@revoke_form["target_user_id"]}
                      placeholder="User ID (or leave empty for group)"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Group ID</th>
                  <td>
                    <input
                      type="text"
                      name="user_group_id"
                      value={@revoke_form["user_group_id"]}
                      placeholder="Group ID (or leave empty for user)"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                <tr>
                  <th class="align-middle">Access Flags</th>
                  <td>
                    <input
                      type="text"
                      name="access_flags"
                      value={@revoke_form["access_flags"]}
                      placeholder="read, write, delete"
                      class="input input-bordered w-full"
                      required
                    />
                    <label class="label">
                      <span class="label-text-alt">Comma-separated list of flags to revoke</span>
                    </label>
                  </td>
                </tr>
              </tbody>
            </table>

            <div class="modal-action">
              <button type="button" phx-click="close_revoke_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-warning #{if @revoke_saving, do: "loading"}"}
                disabled={@revoke_saving}
              >
                Revoke
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop" phx-click="close_revoke_modal"></div>
      </div>
    <% end %>
    </.admin_layout>
    """
  end

  # ============================================================================
  # Grants Tab
  # ============================================================================

  defp grants_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">Grants & Denies</h2>
          <div class="flex gap-2">
            <button phx-click="open_grant_modal" class="btn btn-sm btn-success">Grant</button>
            <button phx-click="open_deny_modal" class="btn btn-sm btn-error">Deny</button>
            <button phx-click="open_revoke_modal" class="btn btn-sm btn-warning">Revoke</button>
            <button
              phx-click="revoke_all"
              data-confirm="Revoke ALL access on this resource? This removes all grants and denies."
              class="btn btn-sm btn-error btn-outline"
            >
              Revoke All
            </button>
          </div>
        </div>

        <%= if @loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <%= if @error do %>
            <div class="alert alert-error mb-4">
              <span><%= @error %></span>
            </div>
          <% end %>

          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <th>User ID</th>
                  <th>Username</th>
                  <th>Group ID</th>
                  <th>Group Title</th>
                  <th>Access Flag</th>
                  <th>Is Deny</th>
                  <th>Granted By</th>
                  <th>Created At</th>
                </tr>
              </thead>
              <tbody>
                <%= for grant <- @grants do %>
                  <tr>
                    <td><%= Map.get(grant, :user_id) || Map.get(grant, :target_user_id) || "-" %></td>
                    <td><%= Map.get(grant, :username) || Map.get(grant, :target_username) || "-" %></td>
                    <td><%= Map.get(grant, :user_group_id) || "-" %></td>
                    <td><%= Map.get(grant, :user_group_title) || "-" %></td>
                    <td>
                      <code class="text-sm"><%= Map.get(grant, :access_flag) || Map.get(grant, :flag) || "-" %></code>
                    </td>
                    <td>
                      <%= if Map.get(grant, :is_deny) do %>
                        <span class="badge badge-error badge-sm">Deny</span>
                      <% else %>
                        <span class="badge badge-success badge-sm">Grant</span>
                      <% end %>
                    </td>
                    <td><%= Map.get(grant, :granted_by) || Map.get(grant, :created_by) || "-" %></td>
                    <td>
                      <span class="text-xs"><%= format_datetime(Map.get(grant, :created_at) || Map.get(grant, :created)) %></span>
                    </td>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@grants) do %>
                  <tr>
                    <td colspan="8" class="text-center text-base-content/50 py-8">
                      No grants or denies on this resource
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Access Check Tab
  # ============================================================================

  defp access_check_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <%!-- Single User Check --%>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title mb-4">Check Single User Access</h2>

          <form phx-submit="check_access" phx-change="check_access_change">
            <div class="form-control mb-3">
              <label class="label">
                <span class="label-text">User ID</span>
              </label>
              <input
                type="text"
                name="check_user_id"
                value={@check_user_id}
                placeholder="User ID to check"
                class="input input-bordered"
                required
              />
            </div>
            <div class="form-control mb-3">
              <label class="label">
                <span class="label-text">Access Flag</span>
              </label>
              <input
                type="text"
                name="check_flag"
                value={@check_flag}
                placeholder="e.g. read"
                class="input input-bordered"
                required
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Check Access</button>
          </form>

          <%= if @check_error do %>
            <div class="alert alert-error mt-4">
              <span><%= @check_error %></span>
            </div>
          <% end %>

          <%= if @check_result != nil do %>
            <div class={"alert mt-4 #{if @check_result, do: "alert-success", else: "alert-warning"}"}>
              <span>
                <%= if @check_result do %>
                  Access GRANTED
                <% else %>
                  Access DENIED
                <% end %>
              </span>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Bulk Filter --%>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title mb-4">Filter Accessible Resources</h2>

          <form phx-submit="filter_accessible" phx-change="filter_change">
            <div class="form-control mb-3">
              <label class="label">
                <span class="label-text">Resource IDs</span>
              </label>
              <input
                type="text"
                name="filter_ids"
                value={@filter_ids}
                placeholder="1, 2, 3, 4, 5"
                class="input input-bordered"
                required
              />
              <label class="label">
                <span class="label-text-alt">Comma-separated resource IDs</span>
              </label>
            </div>
            <div class="form-control mb-3">
              <label class="label">
                <span class="label-text">Access Flag</span>
              </label>
              <input
                type="text"
                name="filter_flag"
                value={@filter_flag}
                placeholder="e.g. read"
                class="input input-bordered"
                required
              />
            </div>
            <button type="submit" class="btn btn-primary btn-sm">Filter</button>
          </form>

          <%= if @filter_error do %>
            <div class="alert alert-error mt-4">
              <span><%= @filter_error %></span>
            </div>
          <% end %>

          <%= if @filter_result != nil do %>
            <div class="alert alert-info mt-4">
              <div>
                <span class="font-semibold">Accessible IDs:</span>
                <%= if Enum.empty?(@filter_result) do %>
                  <span class="text-base-content/50">None</span>
                <% else %>
                  <%= Enum.join(@filter_result, ", ") %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Flags Tab
  # ============================================================================

  defp flags_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">My Effective Flags</h2>

        <%= if @loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <th>Access Flag</th>
                  <th>Source</th>
                </tr>
              </thead>
              <tbody>
                <%= for flag <- @flags do %>
                  <tr>
                    <td><code class="text-sm"><%= Map.get(flag, :access_flag) || Map.get(flag, :flag) || "-" %></code></td>
                    <td>
                      <span class={"badge badge-sm #{if Map.get(flag, :source) == "direct", do: "badge-primary", else: "badge-secondary"}"}>
                        <%= Map.get(flag, :source) || "-" %>
                      </span>
                    </td>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@flags) do %>
                  <tr>
                    <td colspan="2" class="text-center text-base-content/50 py-8">
                      No flags found for current user on this resource
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Matrix Tab
  # ============================================================================

  defp matrix_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Hierarchical Access Matrix</h2>

        <%= if @loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <%= for key <- matrix_columns(@matrix) do %>
                    <th><%= key %></th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @matrix do %>
                  <tr>
                    <%= for key <- matrix_columns(@matrix) do %>
                      <td><%= format_matrix_cell(Map.get(row, key)) %></td>
                    <% end %>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@matrix) do %>
                  <tr>
                    <td colspan={max(length(matrix_columns(@matrix)), 1)} class="text-center text-base-content/50 py-8">
                      No matrix data found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # User Resources Tab
  # ============================================================================

  defp user_resources_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">User Accessible Resources</h2>

        <form phx-submit="load_user_resources" phx-change="ur_change" class="mb-4">
          <div class="flex items-end gap-4">
            <div class="form-control flex-1">
              <label class="label">
                <span class="label-text">User ID</span>
              </label>
              <input
                type="text"
                name="ur_user_id"
                value={@ur_user_id}
                placeholder="User ID"
                class="input input-bordered"
                required
              />
            </div>
            <div class="form-control flex-1">
              <label class="label">
                <span class="label-text">Resource Type</span>
              </label>
              <input
                type="text"
                name="ur_resource_type"
                value={@ur_resource_type}
                placeholder="e.g. project"
                class="input input-bordered"
                required
              />
            </div>
            <div class="form-control flex-1">
              <label class="label">
                <span class="label-text">Access Flag (optional)</span>
              </label>
              <input
                type="text"
                name="ur_flag"
                value={@ur_flag}
                placeholder="e.g. read"
                class="input input-bordered"
              />
            </div>
            <button type="submit" class={"btn btn-primary #{if @loading, do: "loading"}"} disabled={@loading}>
              Load
            </button>
          </div>
        </form>

        <%= if @error do %>
          <div class="alert alert-error mb-4">
            <span><%= @error %></span>
          </div>
        <% end %>

        <%= if @loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <%= for key <- user_resources_columns(@user_resources) do %>
                    <th><%= key %></th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for resource <- @user_resources do %>
                  <tr>
                    <%= for key <- user_resources_columns(@user_resources) do %>
                      <td><%= format_cell(Map.get(resource, key)) %></td>
                    <% end %>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@user_resources) do %>
                  <tr>
                    <td colspan={max(length(user_resources_columns(@user_resources)), 1)} class="text-center text-base-content/50 py-8">
                      No accessible resources found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Display Helpers
  # ============================================================================

  defp matrix_columns([first | _]) when is_map(first), do: Map.keys(first)
  defp matrix_columns(_), do: []

  defp user_resources_columns([first | _]) when is_map(first), do: Map.keys(first)
  defp user_resources_columns(_), do: []

  defp format_matrix_cell(nil), do: "-"
  defp format_matrix_cell(true), do: Phoenix.HTML.raw(~s(<span class="badge badge-success badge-sm">Yes</span>))
  defp format_matrix_cell(false), do: Phoenix.HTML.raw(~s(<span class="badge badge-error badge-sm">No</span>))
  defp format_matrix_cell(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_matrix_cell(val) when is_binary(val), do: val
  defp format_matrix_cell(val), do: inspect(val)

  defp format_cell(nil), do: "-"
  defp format_cell(true), do: Phoenix.HTML.raw(~s(<span class="badge badge-success badge-sm">Yes</span>))
  defp format_cell(false), do: Phoenix.HTML.raw(~s(<span class="badge badge-error badge-sm">No</span>))
  defp format_cell(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_cell(val) when is_binary(val), do: val
  defp format_cell(val) when is_list(val), do: Enum.join(val, ", ")
  defp format_cell(val), do: inspect(val)

  defp format_datetime(nil), do: "-"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_datetime(val), do: inspect(val)
end
