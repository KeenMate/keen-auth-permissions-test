defmodule KeenAuthPermissionsTestWeb.UserDetailLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.Users
  alias KeenAuthPermissions.Audit
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler

  @default_tenant_id 1
  @default_page_size 50

  @impl true
  def mount(%{"user_id" => user_id_param}, session, socket) do
    user = session["current_user"]

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      target_user_id = String.to_integer(user_id_param)

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
         page_title: "User Detail",
         user: user,
         ctx: ctx,
         target_user_id: target_user_id,
         target_user: nil,
         user_data: nil,
         user_status: nil,
         groups: [],
         permissions: [],
         loading: true,
         error: nil,
         auth_blocked: false,
         auth_warning: false,
         auth_warning_message: "",
         # Tabs
         active_tab: :profile,
         # Edit user data
         editing: false,
         edit_form: %{},
         edit_saving: false,
         edit_error: nil,
         # Events tab
         events: [],
         events_page: 1,
         events_page_size: @default_page_size,
         events_total: 0,
         events_loaded: false,
         events_loading: false,
         # Journal tab
         journal: [],
         journal_page: 1,
         journal_page_size: @default_page_size,
         journal_total: 0,
         journal_loaded: false,
         journal_loading: false
       )
       |> load_user()}
    end
  end

  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_user/1)}
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

    socket = assign(socket, active_tab: tab)

    socket =
      case tab do
        :events ->
          if socket.assigns.events_loaded,
            do: socket,
            else: load_events(socket)

        :journal ->
          if socket.assigns.journal_loaded,
            do: socket,
            else: load_journal(socket)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # ============================================================================
  # Pagination
  # ============================================================================

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = String.to_integer(page)

    case socket.assigns.active_tab do
      :events ->
        {:noreply,
         socket
         |> assign(events_page: page, events_loading: true)
         |> load_events()}

      :journal ->
        {:noreply,
         socket
         |> assign(journal_page: page, journal_loading: true)
         |> load_journal()}

      _ ->
        {:noreply, socket}
    end
  end

  # ============================================================================
  # User state operations
  # ============================================================================

  def handle_event("enable_user", _params, socket) do
    %{ctx: ctx, target_user_id: target_user_id} = socket.assigns

    case Users.enable(ctx, target_user_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User enabled") |> load_user()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enable user: #{inspect(reason)}")}
    end
  end

  def handle_event("disable_user", _params, socket) do
    %{ctx: ctx, target_user_id: target_user_id} = socket.assigns

    case Users.disable(ctx, target_user_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User disabled") |> load_user()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disable user: #{inspect(reason)}")}
    end
  end

  def handle_event("lock_user", _params, socket) do
    %{ctx: ctx, target_user_id: target_user_id} = socket.assigns

    case Users.lock(ctx, target_user_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User locked") |> load_user()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to lock user: #{inspect(reason)}")}
    end
  end

  def handle_event("unlock_user", _params, socket) do
    %{ctx: ctx, target_user_id: target_user_id} = socket.assigns

    case Users.unlock(ctx, target_user_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "User unlocked") |> load_user()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to unlock user: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_user_info", _params, socket) do
    %{ctx: ctx, target_user_id: target_user_id} = socket.assigns

    case Users.delete_info(ctx, target_user_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User info deleted")
         |> push_navigate(to: "/users")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete user info: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Edit user data
  # ============================================================================

  def handle_event("start_editing", _params, socket) do
    user_data = socket.assigns.user_data

    {:noreply,
     assign(socket,
       editing: true,
       edit_error: nil,
       edit_form: %{
         "first_name" => (user_data && user_data.first_name) || "",
         "middle_name" => (user_data && user_data.middle_name) || "",
         "last_name" => (user_data && user_data.last_name) || ""
       }
     )}
  end

  def handle_event("cancel_editing", _params, socket) do
    {:noreply, assign(socket, editing: false, edit_error: nil)}
  end

  def handle_event("edit_form_change", params, socket) do
    {:noreply, assign(socket, edit_form: params)}
  end

  def handle_event("save_user_data", params, socket) do
    %{ctx: ctx, target_user_id: target_user_id} = socket.assigns

    socket = assign(socket, edit_saving: true, edit_error: nil)

    user_data = %{
      "first_name" => blank_to_nil(params["first_name"]),
      "middle_name" => blank_to_nil(params["middle_name"]),
      "last_name" => blank_to_nil(params["last_name"])
    }

    case Users.update_data(ctx, target_user_id, "admin", user_data) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(editing: false, edit_saving: false)
         |> put_flash(:info, "User data updated")
         |> load_user()}

      {:error, reason} ->
        Logger.error("Failed to update user data", reason: inspect(reason))

        {:noreply,
         assign(socket,
           edit_saving: false,
           edit_error: "Failed to update: #{inspect(reason)}"
         )}
    end
  end

  # ============================================================================
  # Data loading
  # ============================================================================

  defp load_user(socket) do
    %{ctx: ctx, user: user, target_user_id: target_user_id} = socket.assigns

    target_user =
      case Users.get_by_id(target_user_id) do
        {:ok, u} -> u
        _ -> nil
      end

    user_data =
      case Users.get_data(user.user_id, target_user_id) do
        {:ok, d} -> d
        _ -> nil
      end

    # get_by_id doesn't return is_active/is_locked, so fetch from search
    user_status =
      case Users.search(ctx, nil, nil, nil, nil, 1, 1000, @default_tenant_id) do
        {:ok, results} ->
          Enum.find(results, fn u -> u.user_id == target_user_id end)

        _ ->
          nil
      end

    groups =
      case Users.list_assigned_groups(user.user_id, target_user_id) do
        {:ok, g} -> g
        _ -> []
      end

    permissions =
      case Users.list_permissions(user.user_id, target_user_id, @default_tenant_id) do
        {:ok, p} -> p
        _ -> []
      end

    error = if is_nil(target_user), do: "User not found", else: nil

    assign(socket,
      target_user: target_user,
      user_data: user_data,
      user_status: user_status,
      groups: groups,
      permissions: permissions,
      loading: false,
      error: error,
      page_title: if(target_user, do: target_user.display_name, else: "User Detail")
    )
  end

  defp load_events(socket) do
    %{ctx: ctx, target_user_id: target_user_id, events_page: page, events_page_size: page_size} =
      socket.assigns

    case Audit.search_user_events(ctx, nil, target_user_id, nil, nil, nil, page, page_size) do
      {:ok, [first | _] = events} ->
        assign(socket,
          events: events,
          events_total: first.total_items,
          events_loaded: true,
          events_loading: false
        )

      {:ok, []} ->
        assign(socket, events: [], events_total: 0, events_loaded: true, events_loading: false)

      {:error, reason} ->
        Logger.error("Failed to load user events", reason: inspect(reason))
        assign(socket, events: [], events_total: 0, events_loaded: true, events_loading: false)
    end
  end

  defp load_journal(socket) do
    %{
      ctx: ctx,
      target_user_id: target_user_id,
      journal_page: page,
      journal_page_size: page_size
    } = socket.assigns

    case Audit.search_journal(
           ctx,
           nil,
           nil,
           nil,
           target_user_id,
           nil,
           nil,
           nil,
           nil,
           nil,
           page,
           page_size,
           @default_tenant_id
         ) do
      {:ok, [first | _] = journal} ->
        assign(socket,
          journal: journal,
          journal_total: first.total_items,
          journal_loaded: true,
          journal_loading: false
        )

      {:ok, []} ->
        assign(socket,
          journal: [],
          journal_total: 0,
          journal_loaded: true,
          journal_loading: false
        )

      {:error, reason} ->
        Logger.error("Failed to load journal entries", reason: inspect(reason))

        assign(socket,
          journal: [],
          journal_total: 0,
          journal_loaded: true,
          journal_loading: false
        )
    end
  end

  defp build_context(%User{} = user) do
    RequestContext.new(user)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_event_listener auth_blocked={@auth_blocked} auth_warning={@auth_warning} auth_warning_message={@auth_warning_message} />
    <.admin_layout current_page={:users}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">
            <%= if @target_user, do: @target_user.display_name, else: "User Detail" %>
          </h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li><a href="/users">Users</a></li>
              <li><%= if @target_user, do: @target_user.display_name, else: "..." %></li>
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

        <%= if @target_user && !@loading do %>
          <%!-- Tab Bar --%>
          <div role="tablist" class="tabs tabs-bordered mb-6">
            <button
              role="tab"
              class={"tab #{if @active_tab == :profile, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="profile"
            >
              Profile
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :groups, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="groups"
            >
              Groups (<%= length(@groups) %>)
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :permissions, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="permissions"
            >
              Permissions (<%= length(@permissions) %>)
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :events, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="events"
            >
              Events
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :journal, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="journal"
            >
              Journal
            </button>
          </div>

          <%!-- Tab Content --%>
          <%= case @active_tab do %>
            <% :profile -> %>
              <.profile_tab
                target_user={@target_user}
                user_data={@user_data}
                user_status={@user_status}
                editing={@editing}
                edit_form={@edit_form}
                edit_saving={@edit_saving}
                edit_error={@edit_error}
              />
            <% :groups -> %>
              <.groups_tab groups={@groups} />
            <% :permissions -> %>
              <.permissions_tab permissions={@permissions} />
            <% :events -> %>
              <.events_tab events={@events} page={@events_page} page_size={@events_page_size} total_items={@events_total} loading={@events_loading} />
            <% :journal -> %>
              <.journal_tab journal={@journal} page={@journal_page} page_size={@journal_page_size} total_items={@journal_total} loading={@journal_loading} />
          <% end %>
        <% end %>
    </.admin_layout>
    """
  end

  # ============================================================================
  # Profile Tab
  # ============================================================================

  defp profile_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl mb-6">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">User Info</h2>
          <div class="flex gap-2">
            <%= unless @editing do %>
              <button phx-click="start_editing" class="btn btn-sm btn-outline">Edit Data</button>
              <button
                phx-click="delete_user_info"
                data-confirm="Are you sure you want to delete this user's info? This action cannot be undone."
                class="btn btn-sm btn-error btn-outline"
              >
                Delete
              </button>
            <% end %>
          </div>
        </div>

        <%= if @editing do %>
          <.edit_user_data_form
            edit_form={@edit_form}
            edit_saving={@edit_saving}
            edit_error={@edit_error}
          />
        <% else %>
          <.info_table target_user={@target_user} user_data={@user_data} user_status={@user_status} />
        <% end %>
      </div>
    </div>

    <%!-- Actions Card --%>
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Actions</h2>
        <div class="flex flex-wrap gap-2">
          <%!-- Enable/Disable --%>
          <%= if @user_status && @user_status.is_active do %>
            <button
              phx-click="disable_user"
              data-confirm="Disable this user? They will not be able to log in."
              class="btn btn-sm btn-warning"
            >
              Disable
            </button>
          <% else %>
            <button phx-click="enable_user" class="btn btn-sm btn-success">
              Enable
            </button>
          <% end %>

          <%!-- Lock/Unlock --%>
          <%= if @user_status && @user_status.is_locked do %>
            <button phx-click="unlock_user" class="btn btn-sm btn-info">
              Unlock
            </button>
          <% else %>
            <button
              phx-click="lock_user"
              data-confirm="Lock this user? They will not be able to log in."
              class="btn btn-sm btn-warning btn-outline"
            >
              Lock
            </button>
          <% end %>
        </div>
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
            <th class="w-48">User ID</th>
            <td><%= @target_user.user_id %></td>
          </tr>
          <tr>
            <th>Username</th>
            <td><%= @target_user.username %></td>
          </tr>
          <tr>
            <th>Email</th>
            <td><%= @target_user.email %></td>
          </tr>
          <tr>
            <th>Display Name</th>
            <td><%= @target_user.display_name %></td>
          </tr>
          <tr>
            <th>Code</th>
            <td><code class="text-sm"><%= @target_user.code %></code></td>
          </tr>
          <tr>
            <th>UUID</th>
            <td><code class="text-sm"><%= @target_user.uuid %></code></td>
          </tr>
          <tr>
            <th>Status</th>
            <td>
              <%= if @user_status do %>
                <div class="flex gap-1">
                  <%= if @user_status.is_active do %>
                    <span class="badge badge-success">Active</span>
                  <% else %>
                    <span class="badge badge-error">Disabled</span>
                  <% end %>
                  <%= if @user_status.is_locked do %>
                    <span class="badge badge-warning">Locked</span>
                  <% end %>
                </div>
              <% else %>
                <span class="text-base-content/30">-</span>
              <% end %>
            </td>
          </tr>
          <tr>
            <th>Type</th>
            <td>
              <%= if @user_status && @user_status.user_type_code do %>
                <span class="badge badge-outline"><%= @user_status.user_type_code %></span>
              <% else %>
                <span class="text-base-content/30">-</span>
              <% end %>
            </td>
          </tr>
          <%= if @user_data do %>
            <tr>
              <th>First Name</th>
              <td><%= @user_data.first_name || "-" %></td>
            </tr>
            <tr>
              <th>Middle Name</th>
              <td><%= @user_data.middle_name || "-" %></td>
            </tr>
            <tr>
              <th>Last Name</th>
              <td><%= @user_data.last_name || "-" %></td>
            </tr>
            <tr>
              <th>Created At</th>
              <td><%= format_datetime(@user_data.created_at) %></td>
            </tr>
            <tr>
              <th>Updated At</th>
              <td><%= format_datetime(@user_data.updated_at) %></td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp edit_user_data_form(assigns) do
    ~H"""
    <%= if @edit_error do %>
      <div class="alert alert-error mb-4">
        <span><%= @edit_error %></span>
      </div>
    <% end %>

    <form phx-submit="save_user_data" phx-change="edit_form_change">
      <div class="form-control mb-3">
        <label class="label">
          <span class="label-text">First Name</span>
        </label>
        <input
          type="text"
          name="first_name"
          value={@edit_form["first_name"]}
          placeholder="First name"
          class="input input-bordered"
        />
      </div>

      <div class="form-control mb-3">
        <label class="label">
          <span class="label-text">Middle Name</span>
        </label>
        <input
          type="text"
          name="middle_name"
          value={@edit_form["middle_name"]}
          placeholder="Middle name"
          class="input input-bordered"
        />
      </div>

      <div class="form-control mb-3">
        <label class="label">
          <span class="label-text">Last Name</span>
        </label>
        <input
          type="text"
          name="last_name"
          value={@edit_form["last_name"]}
          placeholder="Last name"
          class="input input-bordered"
        />
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
  # Groups Tab
  # ============================================================================

  defp groups_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">Groups</h2>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>ID</th>
                <th>Title</th>
                <th>Code</th>
                <th>Membership Type</th>
              </tr>
            </thead>
            <tbody>
              <%= for group <- @groups do %>
                <tr>
                  <td><%= group.user_group_id %></td>
                  <td>
                    <a href={"/groups/#{group.user_group_id}"} class="link link-primary">
                      <%= group.user_group_title %>
                    </a>
                  </td>
                  <td><code class="text-sm"><%= group.user_group_code %></code></td>
                  <td>
                    <span class={"badge #{membership_badge(group.user_group_member_type_code)}"}>
                      <%= group.user_group_member_type_code %>
                    </span>
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@groups) do %>
                <tr>
                  <td colspan="4" class="text-center text-base-content/50 py-8">
                    No groups assigned
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
  # Permissions Tab
  # ============================================================================

  defp permissions_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title">Permissions</h2>
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Permission Code</th>
                <th>Permission Title</th>
                <th>Perm Set</th>
                <th>Group</th>
                <th>Inheritance</th>
              </tr>
            </thead>
            <tbody>
              <%= for perm <- @permissions do %>
                <tr>
                  <td><code class="text-sm"><%= perm.permission_code %></code></td>
                  <td><%= perm.permission_title %></td>
                  <td><%= perm.perm_set_title %></td>
                  <td><%= perm.user_group_title %></td>
                  <td>
                    <span class={"badge #{inheritance_badge(perm.permission_inheritance_type)}"}>
                      <%= perm.permission_inheritance_type %>
                    </span>
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@permissions) do %>
                <tr>
                  <td colspan="5" class="text-center text-base-content/50 py-8">
                    No permissions found
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
  # Events Tab
  # ============================================================================

  defp events_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <%= if @loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <th>Event Type</th>
                  <th>Requester</th>
                  <th>Request Context</th>
                  <th>Created At</th>
                  <th>Details</th>
                </tr>
              </thead>
              <tbody>
                <%= for event <- @events do %>
                  <tr>
                    <td>
                      <span class={"badge badge-sm #{event_badge(event.event_type_code)}"}>
                        <%= event.event_type_code %>
                      </span>
                    </td>
                    <td>
                      <div class="flex flex-col">
                        <span><%= event.requester_username || "-" %></span>
                        <span class="text-xs text-base-content/50">ID: <%= event.requester_user_id || "-" %></span>
                      </div>
                    </td>
                    <td>
                      <%= if is_map(event.request_context) and map_size(event.request_context) > 0 do %>
                        <div class="flex flex-col gap-0.5">
                          <%= if ip = event.request_context["ip"] do %>
                            <span class="badge badge-outline badge-xs"><%= ip %></span>
                          <% end %>
                          <%= for {key, val} <- event.request_context, key not in ["ip", "user_agent", "origin", "request_id"] do %>
                            <span class="badge badge-outline badge-xs"><%= key %>: <%= val %></span>
                          <% end %>
                        </div>
                      <% else %>
                        <span class="text-base-content/30">-</span>
                      <% end %>
                    </td>
                    <td>
                      <span class="text-xs"><%= format_datetime(event.created_at) %></span>
                    </td>
                    <td>
                      <%= if has_event_details?(event) do %>
                        <button class="btn btn-ghost btn-xs" onclick={"modal_event_#{event.user_event_id}.showModal()"}>
                          View
                        </button>
                        <dialog id={"modal_event_#{event.user_event_id}"} class="modal">
                          <div class="modal-box max-w-2xl">
                            <h3 class="font-bold text-lg">Event Details</h3>
                            <%= if is_map(event.request_context) and map_size(event.request_context) > 0 do %>
                              <h4 class="font-semibold text-sm mt-4 mb-2">Request Context</h4>
                              <pre class="bg-base-200 p-4 rounded-lg text-xs overflow-auto max-h-48"><%= Jason.encode!(event.request_context, pretty: true) %></pre>
                            <% end %>
                            <%= if event.event_data && event.event_data != %{} do %>
                              <h4 class="font-semibold text-sm mt-4 mb-2">Event Data</h4>
                              <pre class="bg-base-200 p-4 rounded-lg text-xs overflow-auto max-h-48"><%= Jason.encode!(event.event_data, pretty: true) %></pre>
                            <% end %>
                            <div class="modal-action">
                              <form method="dialog">
                                <button class="btn">Close</button>
                              </form>
                            </div>
                          </div>
                          <form method="dialog" class="modal-backdrop">
                            <button>close</button>
                          </form>
                        </dialog>
                      <% else %>
                        <span class="text-base-content/30">-</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@events) do %>
                  <tr>
                    <td colspan="5" class="text-center text-base-content/50 py-8">
                      No events found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <.pagination page={@page} page_size={@page_size} total_items={@total_items} />
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Journal Tab
  # ============================================================================

  defp journal_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <%= if @loading do %>
          <div class="flex justify-center py-8">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <th>Event Code</th>
                  <th>Category</th>
                  <th>Message</th>
                  <th>Created At</th>
                  <th>Created By</th>
                  <th>Details</th>
                </tr>
              </thead>
              <tbody>
                <%= for entry <- @journal do %>
                  <tr>
                    <td><code class="text-sm"><%= entry.event_code %></code></td>
                    <td>
                      <span class="badge badge-sm badge-ghost"><%= entry.event_category %></span>
                    </td>
                    <td class="max-w-xs truncate" title={entry.message}><%= entry.message %></td>
                    <td>
                      <span class="text-xs"><%= format_datetime(entry.created_at) %></span>
                    </td>
                    <td><%= entry.created_by || "-" %></td>
                    <td>
                      <%= if has_journal_details?(entry) do %>
                        <button class="btn btn-ghost btn-xs" onclick={"modal_journal_#{entry.journal_id}.showModal()"}>
                          View
                        </button>
                        <dialog id={"modal_journal_#{entry.journal_id}"} class="modal">
                          <div class="modal-box max-w-2xl">
                            <h3 class="font-bold text-lg">Journal Entry Details</h3>
                            <%= if is_map(entry.keys) and map_size(entry.keys) > 0 do %>
                              <h4 class="font-semibold text-sm mt-4 mb-2">Keys</h4>
                              <pre class="bg-base-200 p-4 rounded-lg text-xs overflow-auto max-h-48"><%= Jason.encode!(entry.keys, pretty: true) %></pre>
                            <% end %>
                            <%= if is_map(entry.request_context) and map_size(entry.request_context) > 0 do %>
                              <h4 class="font-semibold text-sm mt-4 mb-2">Request Context</h4>
                              <pre class="bg-base-200 p-4 rounded-lg text-xs overflow-auto max-h-48"><%= Jason.encode!(entry.request_context, pretty: true) %></pre>
                            <% end %>
                            <div class="modal-action">
                              <form method="dialog">
                                <button class="btn">Close</button>
                              </form>
                            </div>
                          </div>
                          <form method="dialog" class="modal-backdrop">
                            <button>close</button>
                          </form>
                        </dialog>
                      <% else %>
                        <span class="text-base-content/30">-</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
                <%= if Enum.empty?(@journal) do %>
                  <tr>
                    <td colspan="6" class="text-center text-base-content/50 py-8">
                      No journal entries found
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <.pagination page={@page} page_size={@page_size} total_items={@total_items} />
        <% end %>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp has_event_details?(event) do
    has_context = is_map(event.request_context) and map_size(event.request_context) > 0
    has_data = event.event_data != nil and event.event_data != %{}
    has_context or has_data
  end

  defp has_journal_details?(entry) do
    has_keys = is_map(entry.keys) and map_size(entry.keys) > 0
    has_context = is_map(entry.request_context) and map_size(entry.request_context) > 0
    has_keys or has_context
  end

  defp membership_badge("direct"), do: "badge-primary"
  defp membership_badge("mapping"), do: "badge-secondary"
  defp membership_badge(_), do: "badge-ghost"

  defp inheritance_badge("direct"), do: "badge-primary"
  defp inheritance_badge("inherited"), do: "badge-secondary"
  defp inheritance_badge(_), do: "badge-ghost"

  defp event_badge(type) when type in ["user_logged_in", "user_registered"], do: "badge-success"
  defp event_badge(type) when type in ["user_login_failed"], do: "badge-error"
  defp event_badge(type) when type in ["user_locked", "user_disabled"], do: "badge-warning"
  defp event_badge(_), do: "badge-ghost"

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
