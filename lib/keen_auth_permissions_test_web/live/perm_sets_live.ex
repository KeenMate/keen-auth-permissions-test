defmodule KeenAuthPermissionsTestWeb.PermSetsLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.PermSets
  alias KeenAuthPermissions.Permissions
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User

  @default_tenant_id 1

  @impl true
  def mount(_params, session, socket) do
    user = session["keen_auth_user"]
    ctx = build_context(user)

    {:ok,
     socket
     |> assign(
       page_title: "Permission Sets",
       user: user,
       ctx: ctx,
       search_text: "",
       perm_sets: [],
       loading: true,
       error: nil,
       # Create form
       show_create: false,
       create_title: "",
       create_is_system: false,
       create_is_assignable: true,
       create_permissions: "",
       # Edit form
       editing: nil,
       edit_title: "",
       edit_is_assignable: true,
       # Permissions management
       managing_perms: nil,
       managing_perms_title: "",
       current_permissions: [],
       add_perm_code: "",
       available_permissions: []
     )
     |> load_perm_sets()}
  end

  # ============================================================================
  # Search
  # ============================================================================

  @impl true
  def handle_event("search", %{"search" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(search_text: search_text, loading: true)
     |> load_perm_sets()}
  end

  # ============================================================================
  # Create
  # ============================================================================

  @impl true
  def handle_event("show_create", _params, socket) do
    {:noreply, assign(socket, show_create: true, error: nil)}
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply,
     assign(socket,
       show_create: false,
       create_title: "",
       create_is_system: false,
       create_is_assignable: true,
       create_permissions: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("create", params, socket) do
    %{ctx: ctx} = socket.assigns

    title = String.trim(params["title"] || "")
    is_system = params["is_system"] == "true"
    is_assignable = params["is_assignable"] == "true"

    permissions =
      (params["permissions"] || "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if title == "" do
      {:noreply, assign(socket, error: "Title is required")}
    else
      case PermSets.create(ctx, title, is_system, is_assignable, permissions, @default_tenant_id) do
        {:ok, _result} ->
          {:noreply,
           socket
           |> assign(
             show_create: false,
             create_title: "",
             create_is_system: false,
             create_is_assignable: true,
             create_permissions: "",
             error: nil,
             loading: true
           )
           |> load_perm_sets()}

        {:error, reason} ->
          Logger.error("Failed to create permission set", reason: inspect(reason))
          {:noreply, assign(socket, error: "Failed to create: #{inspect(reason)}")}
      end
    end
  end

  # ============================================================================
  # Edit
  # ============================================================================

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    perm_set_id = String.to_integer(id)
    perm_set = Enum.find(socket.assigns.perm_sets, &(&1.perm_set_id == perm_set_id))

    if perm_set do
      {:noreply,
       assign(socket,
         editing: perm_set_id,
         edit_title: perm_set.title,
         edit_is_assignable: perm_set.is_assignable,
         error: nil
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, error: nil)}
  end

  @impl true
  def handle_event("update", params, socket) do
    %{ctx: ctx, editing: perm_set_id} = socket.assigns

    title = String.trim(params["title"] || "")
    is_assignable = params["is_assignable"] == "true"

    if title == "" do
      {:noreply, assign(socket, error: "Title is required")}
    else
      case PermSets.update(ctx, perm_set_id, title, is_assignable, @default_tenant_id) do
        {:ok, _result} ->
          {:noreply,
           socket
           |> assign(editing: nil, error: nil, loading: true)
           |> load_perm_sets()}

        {:error, reason} ->
          Logger.error("Failed to update permission set", reason: inspect(reason), perm_set_id: perm_set_id)
          {:noreply, assign(socket, error: "Failed to update: #{inspect(reason)}")}
      end
    end
  end

  # ============================================================================
  # Permissions management
  # ============================================================================

  @impl true
  def handle_event("manage_perms", %{"id" => id}, socket) do
    %{ctx: ctx} = socket.assigns
    perm_set_id = String.to_integer(id)
    perm_set = Enum.find(socket.assigns.perm_sets, &(&1.perm_set_id == perm_set_id))

    # Load the perm set with its permissions via list/2
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

    # Load available permissions for autocomplete
    available_permissions =
      case Permissions.search(ctx, nil, true, nil, 1, 200, @default_tenant_id) do
        {:ok, perms} -> perms
        _ -> []
      end

    {:noreply,
     assign(socket,
       managing_perms: perm_set_id,
       managing_perms_title: perm_set && perm_set.title,
       current_permissions: current_permissions,
       add_perm_code: "",
       available_permissions: available_permissions,
       error: nil
     )}
  end

  @impl true
  def handle_event("close_manage_perms", _params, socket) do
    {:noreply,
     assign(socket,
       managing_perms: nil,
       current_permissions: [],
       add_perm_code: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("add_permission", params, socket) do
    %{ctx: ctx, managing_perms: perm_set_id} = socket.assigns

    perm_code = String.trim(params["perm_code"] || "")

    if perm_code == "" do
      {:noreply, assign(socket, error: "Permission code is required")}
    else
      case PermSets.add_permissions(ctx, perm_set_id, [perm_code], @default_tenant_id) do
        {:ok, _result} ->
          # Refresh permissions list and perm sets (for updated count)
          socket = refresh_managed_permissions(socket, perm_set_id)
          {:noreply, assign(socket, add_perm_code: "", error: nil, loading: true) |> load_perm_sets()}

        {:error, reason} ->
          Logger.error("Failed to add permission", reason: inspect(reason))
          {:noreply, assign(socket, error: "Failed to add permission: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("remove_permission", %{"code" => perm_code}, socket) do
    %{ctx: ctx, managing_perms: perm_set_id} = socket.assigns

    case PermSets.delete_permissions(ctx, perm_set_id, [perm_code], @default_tenant_id) do
      {:ok, _result} ->
        socket = refresh_managed_permissions(socket, perm_set_id)
        {:noreply, assign(socket, error: nil, loading: true) |> load_perm_sets()}

      {:error, reason} ->
        Logger.error("Failed to remove permission", reason: inspect(reason))
        {:noreply, assign(socket, error: "Failed to remove permission: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp load_perm_sets(socket) do
    %{ctx: ctx, search_text: search_text} = socket.assigns
    search = if search_text == "", do: nil, else: search_text

    case PermSets.search(ctx, search, nil, nil, 1, 100, @default_tenant_id) do
      {:ok, perm_sets} ->
        assign(socket, perm_sets: perm_sets, loading: false, error: nil)

      {:error, reason} ->
        Logger.error("Failed to load permission sets", reason: inspect(reason))
        assign(socket, perm_sets: [], loading: false, error: "Failed to load permission sets: #{inspect(reason)}")
    end
  end

  defp refresh_managed_permissions(socket, perm_set_id) do
    %{ctx: ctx} = socket.assigns

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

  defp extract_perm_info(%{"code" => code, "title" => title}), do: {code, title}
  defp extract_perm_info(%{"code" => code}), do: {code, ""}
  defp extract_perm_info(%{permission_code: code}), do: {code, ""}
  defp extract_perm_info(perm) when is_binary(perm), do: {perm, ""}
  defp extract_perm_info(perm), do: {inspect(perm), ""}

  defp build_context(nil), do: RequestContext.system_ctx()

  defp build_context(user) do
    keen_user = %User{
      user_id: user.id,
      code: nil,
      uuid: user.uuid,
      username: user.username,
      email: user.email,
      display_name: user.display_name,
      groups: user.roles || [],
      permissions: user.permissions || []
    }

    RequestContext.new(keen_user)
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout current_page={:perm_sets}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Permission Sets</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Permission Sets</li>
            </ul>
          </div>
        </div>

        <%= if @error do %>
          <div class="alert alert-error mb-4">
            <span><%= @error %></span>
          </div>
        <% end %>

        <!-- Search + Create button -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="flex flex-col sm:flex-row gap-4 items-start sm:items-center">
              <form phx-change="search" phx-submit="search" class="flex-1">
                <div class="form-control">
                  <div class="input-group">
                    <input
                      type="text"
                      name="search"
                      value={@search_text}
                      placeholder="Search permission sets..."
                      class="input input-bordered w-full max-w-md"
                      phx-debounce="300"
                    />
                    <%= if @loading do %>
                      <span class="btn btn-square loading"></span>
                    <% end %>
                  </div>
                </div>
              </form>
              <button phx-click="show_create" class="btn btn-primary">
                New Permission Set
              </button>
            </div>
          </div>
        </div>

        <!-- Create form -->
        <%= if @show_create do %>
          <div class="card bg-base-100 shadow-xl mt-4 border-2 border-primary">
            <div class="card-body">
              <h2 class="card-title text-lg">Create Permission Set</h2>
              <form phx-submit="create" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Title</span></label>
                  <input
                    type="text"
                    name="title"
                    value={@create_title}
                    placeholder="Permission set title"
                    class="input input-bordered input-sm"
                    required
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Initial Permissions (comma-separated codes)</span></label>
                  <input
                    type="text"
                    name="permissions"
                    value={@create_permissions}
                    placeholder="perm.code1, perm.code2"
                    class="input input-bordered input-sm"
                  />
                </div>
                <div class="form-control">
                  <label class="label cursor-pointer justify-start gap-3">
                    <input type="hidden" name="is_system" value="false" />
                    <input type="checkbox" name="is_system" value="true" class="checkbox checkbox-sm" checked={@create_is_system} />
                    <span class="label-text">System</span>
                  </label>
                </div>
                <div class="form-control">
                  <label class="label cursor-pointer justify-start gap-3">
                    <input type="hidden" name="is_assignable" value="false" />
                    <input type="checkbox" name="is_assignable" value="true" class="checkbox checkbox-sm" checked={@create_is_assignable} />
                    <span class="label-text">Assignable</span>
                  </label>
                </div>
                <div class="md:col-span-2 flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Create</button>
                  <button type="button" phx-click="cancel_create" class="btn btn-ghost btn-sm">Cancel</button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Permission Sets Table -->
        <div class="card bg-base-100 shadow-xl mt-4">
          <div class="card-body">
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th class="w-1">Actions</th>
                    <th>ID</th>
                    <th>Title</th>
                    <th>Code</th>
                    <th>Type</th>
                    <th>Assignable</th>
                    <th>Permissions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for ps <- @perm_sets do %>
                    <%= if @editing == ps.perm_set_id do %>
                      <tr class="bg-base-200">
                        <td></td>
                        <td><%= ps.perm_set_id %></td>
                        <td colspan="5">
                          <form phx-submit="update" class="flex items-center gap-3">
                            <input
                              type="text"
                              name="title"
                              value={@edit_title}
                              class="input input-bordered input-sm w-48"
                              required
                            />
                            <label class="label cursor-pointer gap-2">
                              <input type="hidden" name="is_assignable" value="false" />
                              <input type="checkbox" name="is_assignable" value="true" class="checkbox checkbox-sm" checked={@edit_is_assignable} />
                              <span class="label-text text-xs">Assignable</span>
                            </label>
                            <button type="submit" class="btn btn-success btn-xs">Save</button>
                            <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-xs">Cancel</button>
                          </form>
                        </td>
                      </tr>
                    <% else %>
                      <tr>
                        <td>
                          <div class="flex gap-1">
                            <.action_icon
                              icon="hero-pencil"
                              color="yellow"
                              tooltip="Edit"
                              phx-click="edit"
                              phx-value-id={ps.perm_set_id}
                            />
                            <.action_icon
                              icon="hero-key"
                              color="blue"
                              tooltip="Manage permissions"
                              phx-click="manage_perms"
                              phx-value-id={ps.perm_set_id}
                            />
                          </div>
                        </td>
                        <td><%= ps.perm_set_id %></td>
                        <td><%= ps.title %></td>
                        <td><code class="text-sm"><%= ps.code %></code></td>
                        <td>
                          <%= if ps.is_system do %>
                            <span class="badge badge-info badge-sm">system</span>
                          <% else %>
                            <span class="badge badge-ghost badge-sm">custom</span>
                          <% end %>
                        </td>
                        <td>
                          <%= if ps.is_assignable do %>
                            <span class="badge badge-success badge-sm">Yes</span>
                          <% else %>
                            <span class="badge badge-ghost badge-sm">No</span>
                          <% end %>
                        </td>
                        <td>
                          <span class="badge badge-outline badge-sm"><%= ps.permission_count %></span>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                  <%= if Enum.empty?(@perm_sets) do %>
                    <tr>
                      <td colspan="7" class="text-center text-base-content/50 py-8">
                        No permission sets found
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <%= if length(@perm_sets) > 0 do %>
              <div class="text-sm text-base-content/50 mt-4">
                Showing <%= length(@perm_sets) %> permission sets
                <%= if length(@perm_sets) > 0 do %>
                  (Total: <%= List.first(@perm_sets).total_items %>)
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Manage Permissions Modal -->
        <%= if @managing_perms do %>
          <div class="modal modal-open">
            <div class="modal-box max-w-2xl">
              <h3 class="font-bold text-lg mb-4">
                Manage Permissions: <%= @managing_perms_title %>
              </h3>

              <!-- Add permission -->
              <form phx-submit="add_permission" class="flex gap-2 mb-4">
                <input
                  type="text"
                  name="perm_code"
                  value={@add_perm_code}
                  placeholder="Permission code to add..."
                  class="input input-bordered input-sm flex-1"
                  list="available-perms"
                />
                <datalist id="available-perms">
                  <%= for perm <- @available_permissions do %>
                    <option value={perm.full_code}><%= perm.title %></option>
                  <% end %>
                </datalist>
                <button type="submit" class="btn btn-primary btn-sm">Add</button>
              </form>

              <!-- Current permissions -->
              <div class="overflow-y-auto max-h-80">
                <%= if is_list(@current_permissions) && length(@current_permissions) > 0 do %>
                  <table class="table table-zebra table-sm">
                    <thead>
                      <tr>
                        <th class="w-1">Actions</th>
                        <th>Code</th>
                        <th>Title</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for perm <- @current_permissions do %>
                        <% {perm_code, perm_title} = extract_perm_info(perm) %>
                        <tr>
                          <td>
                            <.action_icon
                              icon="hero-trash"
                              color="red"
                              tooltip="Remove permission"
                              phx-click="remove_permission"
                              phx-value-code={perm_code}
                            />
                          </td>
                          <td><code class="text-sm"><%= perm_code %></code></td>
                          <td class="text-sm"><%= perm_title %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                <% else %>
                  <div class="text-center text-base-content/50 py-8">
                    No permissions assigned to this set
                  </div>
                <% end %>
              </div>

              <div class="modal-action">
                <button phx-click="close_manage_perms" class="btn">Close</button>
              </div>
            </div>
            <div class="modal-backdrop" phx-click="close_manage_perms">
              <button>close</button>
            </div>
          </div>
        <% end %>
    </.admin_layout>
    """
  end
end
