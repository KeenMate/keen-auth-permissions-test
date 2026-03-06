defmodule KeenAuthPermissionsTestWeb.GroupDetailLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.UserGroups
  alias KeenAuthPermissions.Users
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User
  alias KeenAuthPermissionsTestWeb.AuthEventHandler
  alias KeenAuthPermissionsTestWeb.AadBrowser

  @default_tenant_id 1

  @impl true
  def mount(%{"group_id" => group_id_param}, session, socket) do
    user = session["current_user"]

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/login")}
    else
      group_id = String.to_integer(group_id_param)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(
          KeenAuthPermissionsTest.PubSub,
          "keen_auth:user:#{user.user_id}"
        )
      end

      ctx = build_context(user)
      providers = load_providers()

      {:ok,
       socket
       |> assign(
         page_title: "Group Detail",
         user: user,
         ctx: ctx,
         group_id: group_id,
         group: nil,
         members: [],
         mappings: [],
         permissions: [],
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
         # Add member
         member_search: "",
         member_search_results: [],
         member_searching: false,
         member_add_error: nil,
         # Add member - AAD search
         member_search_mode: :local,
         aad_user_search: "",
         aad_users: [],
         aad_users_loading: false,
         aad_users_error: nil,
         # Add mapping
         providers: providers,
         show_mapping_modal: false,
         mapping_form: %{
           "provider_code" => "",
           "mapped_object_id" => "",
           "mapped_object_name" => "",
           "mapped_role" => ""
         },
         mapping_saving: false,
         mapping_error: nil,
         # AAD group browser
         show_aad_groups_modal: false,
         aad_group_search: "",
         aad_groups: [],
         aad_groups_loading: false,
         aad_groups_error: nil
       )
       |> load_group()}
    end
  end

  @impl true
  def handle_info({:sse_event, event, payload}, socket) do
    {:noreply, AuthEventHandler.handle_sse_event(socket, event, payload, &load_group/1)}
  end

  @impl true
  def handle_event("dismiss_auth_warning", _params, socket) do
    {:noreply, assign(socket, auth_warning: false, auth_warning_message: "")}
  end

  # ============================================================================
  # Tab switching
  # ============================================================================

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  # ============================================================================
  # Edit group
  # ============================================================================

  def handle_event("start_editing", _params, socket) do
    group = socket.assigns.group

    {:noreply,
     assign(socket,
       editing: true,
       edit_error: nil,
       edit_form: %{
         "title" => group.title,
         "is_assignable" => to_string(group.is_assignable),
         "is_active" => to_string(group.is_active),
         "is_external" => to_string(group.is_external),
         "is_default" => to_string(group.is_default)
       }
     )}
  end

  def handle_event("cancel_editing", _params, socket) do
    {:noreply, assign(socket, editing: false, edit_error: nil)}
  end

  def handle_event("edit_form_change", params, socket) do
    {:noreply, assign(socket, edit_form: params)}
  end

  def handle_event("save_group", params, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    title = String.trim(params["title"] || "")

    if title == "" do
      {:noreply, assign(socket, edit_error: "Title is required")}
    else
      socket = assign(socket, edit_saving: true, edit_error: nil)

      case UserGroups.update(
             ctx,
             group_id,
             title,
             params["is_assignable"] == "true",
             params["is_active"] == "true",
             params["is_external"] == "true",
             params["is_default"] == "true",
             @default_tenant_id
           ) do
        {:ok, _group} ->
          {:noreply,
           socket
           |> assign(editing: false, edit_saving: false)
           |> put_flash(:info, "Group updated successfully")
           |> load_group()}

        {:error, reason} ->
          Logger.error("Failed to update group", reason: inspect(reason))

          {:noreply,
           assign(socket,
             edit_saving: false,
             edit_error: "Failed to update group: #{inspect(reason)}"
           )}
      end
    end
  end

  # ============================================================================
  # Delete group
  # ============================================================================

  def handle_event("delete_group", _params, socket) do
    %{ctx: ctx, group_id: group_id, group: group} = socket.assigns

    case UserGroups.delete(ctx, group_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group \"#{group.title}\" deleted")
         |> push_navigate(to: "/groups")}

      {:error, reason} ->
        Logger.error("Failed to delete group", reason: inspect(reason))

        {:noreply,
         socket
         |> put_flash(:error, "Failed to delete group: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Group state operations
  # ============================================================================

  def handle_event("enable_group", _params, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    case UserGroups.enable(ctx, group_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Group enabled") |> load_group()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enable group: #{inspect(reason)}")}
    end
  end

  def handle_event("disable_group", _params, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    case UserGroups.disable(ctx, group_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Group disabled") |> load_group()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to disable group: #{inspect(reason)}")}
    end
  end

  def handle_event("lock_group", _params, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    case UserGroups.lock(ctx, group_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Group locked") |> load_group()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to lock group: #{inspect(reason)}")}
    end
  end

  def handle_event("unlock_group", _params, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    case UserGroups.unlock(ctx, group_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Group unlocked") |> load_group()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to unlock group: #{inspect(reason)}")}
    end
  end

  def handle_event("set_type", %{"type" => type}, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    result =
      case type do
        "internal" -> UserGroups.set_as_internal(ctx, group_id, @default_tenant_id)
        "external" -> UserGroups.set_as_external(ctx, group_id, @default_tenant_id)
        "hybrid" -> UserGroups.set_as_hybrid(ctx, group_id, @default_tenant_id)
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Group type set to #{type}") |> load_group()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to set group type: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Member management
  # ============================================================================

  def handle_event("search_users", %{"member_search" => search_text}, socket) do
    if String.trim(search_text) == "" do
      {:noreply, assign(socket, member_search: search_text, member_search_results: [])}
    else
      %{ctx: ctx} = socket.assigns

      results =
        case Users.search(ctx, search_text, nil, nil, nil, 1, 10, @default_tenant_id) do
          {:ok, users} -> users
          _ -> []
        end

      {:noreply,
       assign(socket,
         member_search: search_text,
         member_search_results: results,
         member_searching: false
       )}
    end
  end

  def handle_event("add_member", %{"user_id" => user_id_str}, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns
    target_user_id = String.to_integer(user_id_str)

    case UserGroups.add_member(ctx, group_id, target_user_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(member_search: "", member_search_results: [], member_add_error: nil)
         |> put_flash(:info, "Member added")
         |> reload_members()}

      {:error, reason} ->
        Logger.error("Failed to add member", reason: inspect(reason))

        {:noreply, assign(socket, member_add_error: "Failed to add member: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_member", %{"user_id" => user_id_str}, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns
    target_user_id = String.to_integer(user_id_str)

    case UserGroups.remove_member(ctx, group_id, target_user_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Member removed")
         |> reload_members()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to remove member: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Mapping management
  # ============================================================================

  def handle_event("open_mapping_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_mapping_modal: true,
       mapping_form: %{
         "provider_code" => "",
         "mapped_object_id" => "",
         "mapped_object_name" => "",
         "mapped_role" => ""
       },
       mapping_error: nil
     )}
  end

  def handle_event("close_mapping_modal", _params, socket) do
    {:noreply, assign(socket, show_mapping_modal: false, mapping_error: nil)}
  end

  def handle_event("mapping_form_change", params, socket) do
    {:noreply, assign(socket, mapping_form: params)}
  end

  def handle_event("create_mapping", params, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    provider_code = String.trim(params["provider_code"] || "")

    if provider_code == "" do
      {:noreply, assign(socket, mapping_error: "Provider code is required")}
    else
      socket = assign(socket, mapping_saving: true, mapping_error: nil)

      case UserGroups.create_mapping(
             ctx,
             group_id,
             provider_code,
             blank_to_nil(params["mapped_object_id"]),
             blank_to_nil(params["mapped_object_name"]),
             blank_to_nil(params["mapped_role"]),
             @default_tenant_id
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(show_mapping_modal: false, mapping_saving: false)
           |> put_flash(:info, "Mapping created")
           |> reload_mappings()}

        {:error, reason} ->
          Logger.error("Failed to create mapping", reason: inspect(reason))

          {:noreply,
           assign(socket,
             mapping_saving: false,
             mapping_error: "Failed to create mapping: #{inspect(reason)}"
           )}
      end
    end
  end

  def handle_event("delete_mapping", %{"mapping_id" => mapping_id_str}, socket) do
    %{ctx: ctx} = socket.assigns
    mapping_id = String.to_integer(mapping_id_str)

    case UserGroups.delete_mapping(ctx, mapping_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Mapping deleted")
         |> reload_mappings()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete mapping: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # AAD Group browser (Mappings tab)
  # ============================================================================

  def handle_event("open_aad_groups", _params, socket) do
    socket =
      assign(socket, show_aad_groups_modal: true, aad_groups_loading: true, aad_groups_error: nil)

    case AadBrowser.search_groups("") do
      {:ok, groups} ->
        {:noreply, assign(socket, aad_groups: groups, aad_groups_loading: false)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           aad_groups: [],
           aad_groups_loading: false,
           aad_groups_error: "Failed to load AAD groups: #{inspect(reason)}"
         )}
    end
  end

  def handle_event("close_aad_groups", _params, socket) do
    {:noreply,
     assign(socket,
       show_aad_groups_modal: false,
       aad_group_search: "",
       aad_groups: [],
       aad_groups_error: nil
     )}
  end

  def handle_event("search_aad_groups", %{"aad_group_search" => search_text}, socket) do
    socket =
      assign(socket,
        aad_group_search: search_text,
        aad_groups_loading: true,
        aad_groups_error: nil
      )

    case AadBrowser.search_groups(search_text) do
      {:ok, groups} ->
        {:noreply, assign(socket, aad_groups: groups, aad_groups_loading: false)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           aad_groups: [],
           aad_groups_loading: false,
           aad_groups_error: "Search failed: #{inspect(reason)}"
         )}
    end
  end

  def handle_event("select_aad_group", %{"id" => group_id, "name" => group_name}, socket) do
    {:noreply,
     assign(socket,
       show_aad_groups_modal: false,
       aad_group_search: "",
       aad_groups: [],
       aad_groups_error: nil,
       show_mapping_modal: true,
       mapping_form: %{
         "provider_code" => "entra",
         "mapped_object_id" => group_id,
         "mapped_object_name" => group_name,
         "mapped_role" => ""
       },
       mapping_error: nil
     )}
  end

  # ============================================================================
  # AAD User search (Members tab)
  # ============================================================================

  def handle_event("toggle_member_search_mode", %{"mode" => mode}, socket) do
    mode = String.to_existing_atom(mode)

    {:noreply,
     assign(socket,
       member_search_mode: mode,
       member_search: "",
       member_search_results: [],
       aad_user_search: "",
       aad_users: [],
       aad_users_error: nil
     )}
  end

  def handle_event("search_aad_users", %{"aad_user_search" => search_text}, socket) do
    if String.trim(search_text) == "" do
      {:noreply, assign(socket, aad_user_search: search_text, aad_users: [])}
    else
      socket =
        assign(socket,
          aad_user_search: search_text,
          aad_users_loading: true,
          aad_users_error: nil
        )

      case AadBrowser.search_users(search_text) do
        {:ok, users} ->
          {:noreply, assign(socket, aad_users: users, aad_users_loading: false)}

        {:error, reason} ->
          {:noreply,
           assign(socket,
             aad_users: [],
             aad_users_loading: false,
             aad_users_error: "Search failed: #{inspect(reason)}"
           )}
      end
    end
  end

  def handle_event("add_aad_member", %{"aad_oid" => aad_oid, "display_name" => display_name, "email" => email}, socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    with {:ok, local_user} <- ensure_local_user(ctx, aad_oid, display_name, email),
         {:ok, _} <- UserGroups.add_member(ctx, group_id, local_user.user_id, @default_tenant_id) do
      {:noreply,
       socket
       |> assign(aad_users_error: nil)
       |> put_flash(:info, "Member added")
       |> reload_members()}
    else
      {:error, reason} ->
        Logger.error("Failed to add AAD member", reason: inspect(reason))
        {:noreply, assign(socket, aad_users_error: "Failed to add member: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # AAD user helpers
  # ============================================================================

  defp ensure_local_user(ctx, aad_oid, display_name, email) do
    case Users.get_by_provider_oid(ctx.user.user_id, aad_oid) do
      {:ok, _local_user} = ok ->
        ok

      {:error, _} ->
        # User hasn't signed in yet — create them via ensure_info
        Users.ensure_info(ctx, aad_oid, display_name, "entra", email)
    end
  end

  # ============================================================================
  # Data loading
  # ============================================================================

  defp load_group(socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    group =
      case UserGroups.get_by_id(ctx, group_id, @default_tenant_id) do
        {:ok, g} -> g
        _ -> nil
      end

    members =
      case UserGroups.list_members(ctx, group_id, @default_tenant_id) do
        {:ok, m} -> m
        _ -> []
      end

    mappings =
      case UserGroups.list_mappings(ctx, group_id, @default_tenant_id) do
        {:ok, m} -> m
        _ -> []
      end

    permissions =
      case UserGroups.list_effective_permissions(ctx, group_id, @default_tenant_id) do
        {:ok, p} -> p
        _ -> []
      end

    error = if is_nil(group), do: "Group not found", else: nil

    assign(socket,
      group: group,
      members: members,
      mappings: mappings,
      permissions: permissions,
      loading: false,
      error: error,
      page_title: if(group, do: group.title, else: "Group Detail")
    )
  end

  defp reload_members(socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    members =
      case UserGroups.list_members(ctx, group_id, @default_tenant_id) do
        {:ok, m} -> m
        _ -> []
      end

    assign(socket, members: members)
  end

  defp reload_mappings(socket) do
    %{ctx: ctx, group_id: group_id} = socket.assigns

    mappings =
      case UserGroups.list_mappings(ctx, group_id, @default_tenant_id) do
        {:ok, m} -> m
        _ -> []
      end

    assign(socket, mappings: mappings)
  end

  defp build_context(%User{} = user) do
    RequestContext.new(user)
  end

  defp load_providers do
    keen_auth_config = Application.get_env(:keen_auth_permissions_test, :keen_auth, [])
    strategies = Keyword.get(keen_auth_config, :strategies, [])

    Enum.map(strategies, fn {key, opts} ->
      %{code: to_string(key), label: Keyword.get(opts, :label, to_string(key))}
    end)
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
    <.auth_event_listener
      auth_blocked={@auth_blocked}
      auth_warning={@auth_warning}
      auth_warning_message={@auth_warning_message}
    />
    <.admin_layout current_page={:groups}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">{if @group, do: @group.title, else: "Group Detail"}</h1>
          
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              
              <li><a href="/dashboard">Dashboard</a></li>
              
              <li><a href="/groups">Groups</a></li>
              
              <li>{if @group, do: @group.title, else: "..."}</li>
            </ul>
          </div>
        </div>
        
        <%= if @error do %>
          <div class="alert alert-error mb-6"><span>{@error}</span></div>
        <% end %>
        
        <%= if @loading do %>
          <div class="flex justify-center py-12">
            <span class="loading loading-spinner loading-lg"></span>
          </div>
        <% end %>
        
        <%= if @group && !@loading do %>
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
              Members ({length(@members)})
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :mappings, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="mappings"
            >
              Mappings ({length(@mappings)})
            </button>
            <button
              role="tab"
              class={"tab #{if @active_tab == :permissions, do: "tab-active"}"}
              phx-click="switch_tab"
              phx-value-tab="permissions"
            >
              Permissions
            </button>
          </div>
           <%!-- Tab Content --%>
          <%= case @active_tab do %>
            <% :info -> %>
              <.info_tab
                group={@group}
                editing={@editing}
                edit_form={@edit_form}
                edit_saving={@edit_saving}
                edit_error={@edit_error}
              />
            <% :members -> %>
              <.members_tab
                members={@members}
                member_search={@member_search}
                member_search_results={@member_search_results}
                member_add_error={@member_add_error}
                existing_member_ids={MapSet.new(@members, & &1.user_id)}
                member_search_mode={@member_search_mode}
                aad_user_search={@aad_user_search}
                aad_users={@aad_users}
                aad_users_loading={@aad_users_loading}
                aad_users_error={@aad_users_error}
              />
            <% :mappings -> %>
              <.mappings_tab
                mappings={@mappings}
                providers={@providers}
                show_mapping_modal={@show_mapping_modal}
                mapping_form={@mapping_form}
                mapping_saving={@mapping_saving}
                mapping_error={@mapping_error}
                show_aad_groups_modal={@show_aad_groups_modal}
                aad_group_search={@aad_group_search}
                aad_groups={@aad_groups}
                aad_groups_loading={@aad_groups_loading}
                aad_groups_error={@aad_groups_error}
              />
            <% :permissions -> %>
              <.permissions_tab permissions={@permissions} />
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
    <div class="card bg-base-100 shadow-xl mb-6">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">Group Info</h2>
          
          <div class="flex gap-2">
            <%= unless @editing do %>
              <button phx-click="start_editing" class="btn btn-sm btn-outline">Edit</button>
              <button
                phx-click="delete_group"
                data-confirm="Are you sure you want to delete this group? This action cannot be undone."
                class="btn btn-sm btn-error btn-outline"
                disabled={@group.is_system}
              >
                Delete
              </button>
            <% end %>
          </div>
        </div>
        
        <%= if @editing do %>
          <.edit_form
            edit_form={@edit_form}
            edit_saving={@edit_saving}
            edit_error={@edit_error}
            is_system={@group.is_system}
          />
        <% else %>
          <.info_table group={@group} />
        <% end %>
      </div>
    </div>
     <%!-- Actions Card --%>
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Actions</h2>
        
        <div class="flex flex-wrap gap-2">
          <%!-- Enable/Disable --%>
          <%= if @group.is_active do %>
            <button
              phx-click="disable_group"
              data-confirm="Disable this group? All members will be notified."
              class="btn btn-sm btn-warning"
            >
              Disable
            </button>
          <% else %>
            <button phx-click="enable_group" class="btn btn-sm btn-success">Enable</button>
          <% end %>
           <%!-- Group Type --%>
          <div class="dropdown">
            <div tabindex="0" role="button" class="btn btn-sm btn-outline">
              Set Type: {group_type_label(@group)}
            </div>
            
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-44"
            >
              <li>
                <button
                  phx-click="set_type"
                  phx-value-type="internal"
                  class={if !@group.is_external, do: "active"}
                >
                  Internal
                </button>
              </li>
              
              <li>
                <button
                  phx-click="set_type"
                  phx-value-type="external"
                  class={if @group.is_external, do: "active"}
                >
                  External
                </button>
              </li>
              
              <li><button phx-click="set_type" phx-value-type="hybrid">Hybrid</button></li>
            </ul>
          </div>
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
            <th class="w-48">Group ID</th>
            
            <td>{@group.user_group_id}</td>
          </tr>
          
          <tr>
            <th>Title</th>
            
            <td>{@group.title}</td>
          </tr>
          
          <tr>
            <th>Code</th>
            
            <td><code class="text-sm">{@group.code}</code></td>
          </tr>
          
          <tr>
            <th>Status</th>
            
            <td>
              <%= if @group.is_active do %>
                <span class="badge badge-success">Active</span>
              <% else %>
                <span class="badge badge-error">Disabled</span>
              <% end %>
            </td>
          </tr>
          
          <tr>
            <th>Type</th>
            
            <td>
              <span class={"badge #{type_badge(@group)}"}>{group_type_label(@group)}</span>
              <%= if @group.is_system do %>
                <span class="badge badge-info ml-1">system</span>
              <% end %>
              
              <div class="mt-3 text-xs text-base-content/60 space-y-1">
                <p>
                  <span class="font-semibold">Internal</span> — members managed manually by admins
                </p>
                
                <p>
                  <span class="font-semibold">External</span>
                  — members synced from an external provider (e.g. Azure AD)
                </p>
                
                <p>
                  <span class="font-semibold">Hybrid</span>
                  — combines both manual and provider-synced members
                </p>
              </div>
            </td>
          </tr>
          
          <tr>
            <th>Assignable</th>
            
            <td>{if @group.is_assignable, do: "Yes", else: "No"}</td>
          </tr>
          
          <tr>
            <th>Default</th>
            
            <td>{if @group.is_default, do: "Yes", else: "No"}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp edit_form(assigns) do
    ~H"""
    <%= if @edit_error do %>
      <div class="alert alert-error mb-4"><span>{@edit_error}</span></div>
    <% end %>

    <form phx-submit="save_group" phx-change="edit_form_change">
      <div class="form-control mb-3">
        <label class="label"><span class="label-text">Title</span></label>
        <input
          type="text"
          name="title"
          value={@edit_form["title"]}
          class="input input-bordered"
          required
        />
      </div>
      
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
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
        
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Active</span>
            <input type="hidden" name="is_active" value="false" />
            <input
              type="checkbox"
              name="is_active"
              value="true"
              checked={@edit_form["is_active"] == "true"}
              class="checkbox"
            />
          </label>
        </div>
        
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">External</span>
            <input type="hidden" name="is_external" value="false" />
            <input
              type="checkbox"
              name="is_external"
              value="true"
              checked={@edit_form["is_external"] == "true"}
              class="checkbox"
            />
          </label>
        </div>
        
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Default</span>
            <input type="hidden" name="is_default" value="false" />
            <input
              type="checkbox"
              name="is_default"
              value="true"
              checked={@edit_form["is_default"] == "true"}
              class="checkbox"
            />
          </label>
        </div>
      </div>
      
      <div class="flex gap-2 mt-4">
        <button type="button" phx-click="cancel_editing" class="btn btn-ghost">Cancel</button>
        <button
          type="submit"
          class={"btn btn-primary #{if @edit_saving, do: "loading"}"}
          disabled={@edit_saving}
        >
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
    <div class="card bg-base-100 shadow-xl mb-6">
      <div class="card-body">
        <h2 class="card-title mb-4">Add Member</h2>
        
        <%= if @member_add_error do %>
          <div class="alert alert-error mb-4"><span>{@member_add_error}</span></div>
        <% end %>
         <%!-- Search mode toggle --%>
        <div class="tabs tabs-boxed mb-4 w-fit">
          <a
            class={"tab #{if @member_search_mode == :local, do: "tab-active"}"}
            phx-click="toggle_member_search_mode"
            phx-value-mode="local"
          >
            Local Users
          </a>
          <a
            class={"tab #{if @member_search_mode == :aad, do: "tab-active"}"}
            phx-click="toggle_member_search_mode"
            phx-value-mode="aad"
          >
            AAD Users
          </a>
        </div>
        
        <%= if @member_search_mode == :local do %>
          <%!-- Local user search --%>
          <form phx-change="search_users" phx-submit="search_users">
            <input
              type="text"
              name="member_search"
              value={@member_search}
              placeholder="Search users by name, email..."
              class="input input-bordered w-full max-w-md"
              phx-debounce="300"
              autocomplete="off"
            />
          </form>
          
          <%= if @member_search != "" and length(@member_search_results) > 0 do %>
            <div class="overflow-x-auto mt-2">
              <table class="table table-sm table-zebra">
                <thead>
                  <tr>
                    <th class="w-1">Actions</th>
                    <th>User</th>
                    <th>Email</th>
                    <th>Status</th>
                  </tr>
                </thead>

                <tbody>
                  <%= for user <- @member_search_results do %>
                    <tr>
                      <td>
                        <%= if MapSet.member?(@existing_member_ids, user.user_id) do %>
                          <span class="badge badge-ghost badge-sm">Already member</span>
                        <% else %>
                          <button
                            phx-click="add_member"
                            phx-value-user_id={user.user_id}
                            class="btn btn-primary btn-xs"
                          >
                            Add
                          </button>
                        <% end %>
                      </td>

                      <td>
                        <div class="flex flex-col">
                          <span class="font-medium">{user.display_name}</span>
                          <span class="text-xs text-base-content/50">ID: {user.user_id}</span>
                        </div>
                      </td>

                      <td>{user.email}</td>

                      <td>
                        <%= if user.is_active do %>
                          <span class="badge badge-success badge-sm">Active</span>
                        <% else %>
                          <span class="badge badge-error badge-sm">Disabled</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
          
          <%= if @member_search != "" and Enum.empty?(@member_search_results) do %>
            <p class="text-base-content/50 text-sm mt-2">No users found</p>
          <% end %>
        <% else %>
          <%!-- AAD user search --%>
          <%= if @aad_users_error do %>
            <div class="alert alert-error mb-4"><span>{@aad_users_error}</span></div>
          <% end %>
          
          <form phx-change="search_aad_users" phx-submit="search_aad_users">
            <input
              type="text"
              name="aad_user_search"
              value={@aad_user_search}
              placeholder="Search AAD users by name..."
              class="input input-bordered w-full max-w-md"
              phx-debounce="500"
              autocomplete="off"
            />
          </form>
          
          <%= if @aad_users_loading do %>
            <div class="flex justify-center py-4">
              <span class="loading loading-spinner loading-sm"></span>
            </div>
          <% end %>
          
          <%= if @aad_user_search != "" and length(@aad_users) > 0 and !@aad_users_loading do %>
            <div class="overflow-x-auto mt-2">
              <table class="table table-sm table-zebra">
                <thead>
                  <tr>
                    <th class="w-1">Actions</th>
                    <th>Display Name</th>
                    <th>Email / UPN</th>
                    <th>Job Title</th>
                    <th>Enabled</th>
                  </tr>
                </thead>

                <tbody>
                  <%= for aad_user <- @aad_users do %>
                    <tr>
                      <td>
                        <button
                          phx-click="add_aad_member"
                          phx-value-aad_oid={aad_user.id}
                          phx-value-display_name={aad_user.display_name}
                          phx-value-email={aad_user.mail || aad_user.user_principal_name}
                          class="btn btn-primary btn-xs"
                        >
                          Add
                        </button>
                      </td>

                      <td class="font-medium">{aad_user.display_name}</td>

                      <td class="text-sm">{aad_user.mail || aad_user.user_principal_name}</td>

                      <td class="text-sm">{aad_user.job_title || "-"}</td>

                      <td>
                        <%= if aad_user.account_enabled do %>
                          <span class="badge badge-success badge-sm">Yes</span>
                        <% else %>
                          <span class="badge badge-error badge-sm">No</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
          
          <%= if @aad_user_search != "" and Enum.empty?(@aad_users) and !@aad_users_loading do %>
            <p class="text-base-content/50 text-sm mt-2">No AAD users found</p>
          <% end %>
        <% end %>
      </div>
    </div>

    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Current Members ({length(@members)})</h2>
        
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th class="w-1">Actions</th>
                <th>User ID</th>
                <th>Display Name</th>
                <th>Membership Type</th>
                <th>Status</th>
              </tr>
            </thead>

            <tbody>
              <%= for member <- @members do %>
                <tr>
                  <td>
                    <%= if member.member_type_code == "manual" do %>
                      <.action_icon
                        icon="hero-trash"
                        color="red"
                        tooltip="Remove member"
                        confirm={"Remove #{member.user_display_name} from this group?"}
                        phx-click="remove_member"
                        phx-value-user_id={member.user_id}
                      />
                    <% end %>
                  </td>

                  <td>{member.user_id}</td>

                  <td>
                    <a href={"/users/#{member.user_id}"} class="link link-primary">
                      {member.user_display_name}
                    </a>
                  </td>

                  <td>
                    <span class={"badge #{membership_badge(member.member_type_code)}"}>
                      {member.member_type_code}
                    </span>
                    <%= if member.member_type_code == "mapping" and member.mapping_provider_code do %>
                      <span class="text-xs text-base-content/50 ml-1">
                        via {member.mapping_provider_code} {if member.mapping_mapped_object_name,
                          do: "(#{member.mapping_mapped_object_name})"}
                      </span>
                    <% end %>
                  </td>

                  <td>
                    <%= if member.user_is_active do %>
                      <span class="badge badge-success badge-sm">Active</span>
                    <% else %>
                      <span class="badge badge-error badge-sm">Disabled</span>
                    <% end %>

                    <%= if member.user_is_locked do %>
                      <span class="badge badge-warning badge-sm">Locked</span>
                    <% end %>
                  </td>
                </tr>
              <% end %>

              <%= if Enum.empty?(@members) do %>
                <tr>
                  <td colspan="5" class="text-center text-base-content/50">No members</td>
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
  # Mappings Tab
  # ============================================================================

  defp mappings_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <div class="flex justify-between items-center mb-4">
          <h2 class="card-title">Provider Mappings</h2>
          
          <div class="flex gap-2">
            <button phx-click="open_aad_groups" class="btn btn-secondary btn-sm">
              Browse AAD Groups
            </button>
            <button phx-click="open_mapping_modal" class="btn btn-primary btn-sm">Add Mapping</button>
          </div>
        </div>
        
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th class="w-1">Actions</th>
                <th>ID</th>
                <th>Provider</th>
                <th>Object ID</th>
                <th>Object Name</th>
                <th>Role</th>
                <th>Created</th>
              </tr>
            </thead>

            <tbody>
              <%= for mapping <- @mappings do %>
                <tr>
                  <td>
                    <.action_icon
                      icon="hero-trash"
                      color="red"
                      tooltip="Delete mapping"
                      confirm="Delete this mapping? Mapped members may be removed."
                      phx-click="delete_mapping"
                      phx-value-mapping_id={mapping.user_group_mapping_id}
                    />
                  </td>

                  <td>{mapping.user_group_mapping_id}</td>

                  <td><code class="text-sm">{mapping.provider_code}</code></td>

                  <td><code class="text-sm">{mapping.mapped_object_id || "-"}</code></td>

                  <td>{mapping.mapped_object_name || "-"}</td>

                  <td>{mapping.mapped_role || "-"}</td>

                  <td><span class="text-xs">{format_datetime(mapping.created_at)}</span></td>
                </tr>
              <% end %>

              <%= if Enum.empty?(@mappings) do %>
                <tr>
                  <td colspan="7" class="text-center text-base-content/50">No mappings configured</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
     <%!-- Create Mapping Modal --%>
    <%= if @show_mapping_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-2xl">
          <h3 class="font-bold text-lg mb-6">Add Provider Mapping</h3>
          
          <%= if @mapping_error do %>
            <div class="alert alert-error mb-4"><span>{@mapping_error}</span></div>
          <% end %>
          
          <form phx-submit="create_mapping" phx-change="mapping_form_change">
            <table class="table">
              <tbody>
                <tr>
                  <th class="w-48 align-middle">Provider</th>
                  
                  <td>
                    <select
                      name="provider_code"
                      class="select select-bordered w-full"
                      required
                    >
                      <option value="" disabled selected={@mapping_form["provider_code"] == ""}>
                        Select a provider
                      </option>
                      
                      <%= for provider <- @providers do %>
                        <option
                          value={provider.code}
                          selected={@mapping_form["provider_code"] == provider.code}
                        >
                          {provider.label}
                        </option>
                      <% end %>
                    </select>
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Mapped Object ID</th>
                  
                  <td>
                    <input
                      type="text"
                      name="mapped_object_id"
                      value={@mapping_form["mapped_object_id"]}
                      placeholder="External group/role ID"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Mapped Object Name</th>
                  
                  <td>
                    <input
                      type="text"
                      name="mapped_object_name"
                      value={@mapping_form["mapped_object_name"]}
                      placeholder="Display name"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
                
                <tr>
                  <th class="align-middle">Mapped Role</th>
                  
                  <td>
                    <input
                      type="text"
                      name="mapped_role"
                      value={@mapping_form["mapped_role"]}
                      placeholder="Role name"
                      class="input input-bordered w-full"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
            
            <div class="modal-action">
              <button type="button" phx-click="close_mapping_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class={"btn btn-primary #{if @mapping_saving, do: "loading"}"}
                disabled={@mapping_saving}
              >
                Create
              </button>
            </div>
          </form>
        </div>
        
        <div class="modal-backdrop" phx-click="close_mapping_modal"></div>
      </div>
    <% end %>
     <%!-- AAD Groups Browser Modal --%>
    <%= if @show_aad_groups_modal do %>
      <div class="modal modal-open">
        <div class="modal-box w-full max-w-3xl">
          <h3 class="font-bold text-lg mb-4">Browse AAD Groups</h3>
          
          <form phx-change="search_aad_groups" phx-submit="search_aad_groups">
            <input
              type="text"
              name="aad_group_search"
              value={@aad_group_search}
              placeholder="Search AAD groups by name..."
              class="input input-bordered w-full mb-4"
              phx-debounce="500"
              autocomplete="off"
            />
          </form>
          
          <%= if @aad_groups_error do %>
            <div class="alert alert-error mb-4"><span>{@aad_groups_error}</span></div>
          <% end %>
          
          <%= if @aad_groups_loading do %>
            <div class="flex justify-center py-6">
              <span class="loading loading-spinner loading-md"></span>
            </div>
          <% else %>
            <div class="overflow-x-auto max-h-96">
              <table class="table table-sm table-zebra">
                <thead>
                  <tr>
                    <th class="w-1">Actions</th>
                    <th>Display Name</th>
                    <th>Description</th>
                    <th>Type</th>
                  </tr>
                </thead>

                <tbody>
                  <%= for group <- @aad_groups do %>
                    <tr>
                      <td>
                        <button
                          phx-click="select_aad_group"
                          phx-value-id={group.id}
                          phx-value-name={group.display_name}
                          class="btn btn-primary btn-xs"
                        >
                          Select
                        </button>
                      </td>

                      <td class="font-medium">{group.display_name}</td>

                      <td class="text-sm max-w-xs truncate">{group.description || "-"}</td>

                      <td>
                        <%= if group.security_enabled do %>
                          <span class="badge badge-info badge-sm">Security</span>
                        <% end %>

                        <%= if group.mail_enabled do %>
                          <span class="badge badge-secondary badge-sm">Mail</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>

                  <%= if Enum.empty?(@aad_groups) do %>
                    <tr>
                      <td colspan="4" class="text-center text-base-content/50">No groups found</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
          
          <div class="modal-action">
            <button phx-click="close_aad_groups" class="btn">Close</button>
          </div>
        </div>
        
        <div class="modal-backdrop" phx-click="close_aad_groups"></div>
      </div>
    <% end %>
    """
  end

  # ============================================================================
  # Permissions Tab
  # ============================================================================

  defp permissions_tab(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl">
      <div class="card-body">
        <h2 class="card-title mb-4">Effective Permissions</h2>
        
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Permission Code</th>
                
                <th>Permission Title</th>
                
                <th>Perm Set</th>
              </tr>
            </thead>
            
            <tbody>
              <%= for perm <- @permissions do %>
                <tr>
                  <td><code class="text-sm">{perm.full_code}</code></td>
                  
                  <td>{perm.permission_title}</td>
                  
                  <td>{perm.perm_set_title}</td>
                </tr>
              <% end %>
              
              <%= if Enum.empty?(@permissions) do %>
                <tr>
                  <td colspan="3" class="text-center text-base-content/50">No permissions found</td>
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
  defp type_badge(%{is_system: true}), do: "badge-info"
  defp type_badge(_), do: "badge-primary"

  defp group_type_label(%{is_external: true}), do: "external"
  defp group_type_label(%{is_system: true}), do: "system"
  defp group_type_label(_), do: "internal"

  defp membership_badge("direct"), do: "badge-primary"
  defp membership_badge("mapping"), do: "badge-secondary"
  defp membership_badge(_), do: "badge-ghost"

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
