defmodule KeenAuthPermissionsTestWeb.TenantsLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.Tenants
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User

  @impl true
  def mount(_params, session, socket) do
    user = session["keen_auth_user"]
    ctx = build_context(user)

    {:ok,
     socket
     |> assign(
       page_title: "Tenants",
       user: user,
       ctx: ctx,
       search_text: "",
       tenants: [],
       loading: true,
       error: nil,
       # Create form
       show_create: false,
       create_title: "",
       create_code: "",
       create_is_removable: true,
       create_is_assignable: true,
       create_owner_id: "",
       # Edit form
       editing: nil,
       edit_title: "",
       edit_code: "",
       edit_is_removable: true,
       edit_is_assignable: true,
       edit_owner_id: ""
     )
     |> load_tenants()}
  end

  # ============================================================================
  # Search
  # ============================================================================

  @impl true
  def handle_event("search", %{"search" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(search_text: search_text, loading: true)
     |> load_tenants()}
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
       create_code: "",
       create_is_removable: true,
       create_is_assignable: true,
       create_owner_id: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("create", params, socket) do
    %{ctx: ctx} = socket.assigns

    title = String.trim(params["title"] || "")
    code = String.trim(params["code"] || "")
    is_removable = params["is_removable"] == "true"
    is_assignable = params["is_assignable"] == "true"
    owner_id = parse_integer(params["owner_id"])

    cond do
      title == "" ->
        {:noreply, assign(socket, error: "Title is required")}

      code == "" ->
        {:noreply, assign(socket, error: "Code is required")}

      owner_id == nil ->
        {:noreply, assign(socket, error: "Owner ID must be a valid number")}

      true ->
        case Tenants.create(ctx, title, code, is_removable, is_assignable, owner_id) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> assign(
               show_create: false,
               create_title: "",
               create_code: "",
               create_is_removable: true,
               create_is_assignable: true,
               create_owner_id: "",
               error: nil,
               loading: true
             )
             |> load_tenants()}

          {:error, reason} ->
            Logger.error("Failed to create tenant", reason: inspect(reason))
            {:noreply, assign(socket, error: "Failed to create: #{inspect(reason)}")}
        end
    end
  end

  # ============================================================================
  # Edit
  # ============================================================================

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    tenant_id = String.to_integer(id)
    tenant = Enum.find(socket.assigns.tenants, &(&1.tenant_id == tenant_id))

    if tenant do
      {:noreply,
       assign(socket,
         editing: tenant_id,
         edit_title: tenant.title,
         edit_code: tenant.code,
         edit_is_removable: tenant.is_removable,
         edit_is_assignable: tenant.is_assignable,
         edit_owner_id: "",
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
    %{ctx: ctx, editing: tenant_id} = socket.assigns

    title = String.trim(params["title"] || "")
    code = String.trim(params["code"] || "")
    is_removable = params["is_removable"] == "true"
    is_assignable = params["is_assignable"] == "true"
    owner_id = parse_integer(params["owner_id"])

    cond do
      title == "" ->
        {:noreply, assign(socket, error: "Title is required")}

      code == "" ->
        {:noreply, assign(socket, error: "Code is required")}

      true ->
        case Tenants.update(ctx, tenant_id, title, code, is_removable, is_assignable, owner_id || 0) do
          {:ok, _result} ->
            {:noreply,
             socket
             |> assign(editing: nil, error: nil, loading: true)
             |> load_tenants()}

          {:error, reason} ->
            Logger.error("Failed to update tenant", reason: inspect(reason), tenant_id: tenant_id)
            {:noreply, assign(socket, error: "Failed to update: #{inspect(reason)}")}
        end
    end
  end

  # ============================================================================
  # Delete
  # ============================================================================

  @impl true
  def handle_event("delete", %{"uuid" => uuid}, socket) do
    %{ctx: ctx} = socket.assigns

    case Tenants.delete(ctx, uuid) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> assign(error: nil, loading: true)
         |> load_tenants()}

      {:error, reason} ->
        Logger.error("Failed to delete tenant", reason: inspect(reason))
        {:noreply, assign(socket, error: "Failed to delete: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp load_tenants(socket) do
    %{ctx: ctx, search_text: search_text} = socket.assigns
    search = if search_text == "", do: nil, else: search_text

    case Tenants.search(ctx, search, 1, 100) do
      {:ok, tenants} ->
        assign(socket, tenants: tenants, loading: false, error: nil)

      {:error, reason} ->
        Logger.error("Failed to load tenants", reason: inspect(reason))
        assign(socket, tenants: [], loading: false, error: "Failed to load tenants: #{inspect(reason)}")
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

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
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-lg">
        <div class="flex-1">
          <a href="/" class="btn btn-ghost text-xl">KeenAuth Permissions Test</a>
        </div>
        <div class="flex-none gap-2">
          <a href="/dashboard" class="btn btn-ghost">Dashboard</a>
          <a href="/events" class="btn btn-ghost">Events</a>
          <a href="/auth/delete" class="btn btn-ghost text-error">Logout</a>
        </div>
      </div>

      <div class="container mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Tenants</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Tenants</li>
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
                      placeholder="Search tenants..."
                      class="input input-bordered w-full max-w-md"
                      phx-debounce="300"
                    />
                    <%= if @loading do %>
                      <span class="btn btn-square loading"></span>
                    <% end %>
                  </div>
                </div>
              </form>
              <button phx-click="show_create" class="btn btn-primary btn-sm">
                + New Tenant
              </button>
            </div>
          </div>
        </div>

        <!-- Create form -->
        <%= if @show_create do %>
          <div class="card bg-base-100 shadow-xl mt-4 border-2 border-primary">
            <div class="card-body">
              <h2 class="card-title text-lg">Create Tenant</h2>
              <form phx-submit="create" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="form-control">
                  <label class="label"><span class="label-text">Title</span></label>
                  <input
                    type="text"
                    name="title"
                    value={@create_title}
                    placeholder="Tenant title"
                    class="input input-bordered input-sm"
                    required
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Code</span></label>
                  <input
                    type="text"
                    name="code"
                    value={@create_code}
                    placeholder="tenant-code"
                    class="input input-bordered input-sm"
                    required
                  />
                </div>
                <div class="form-control">
                  <label class="label"><span class="label-text">Owner ID</span></label>
                  <input
                    type="text"
                    name="owner_id"
                    value={@create_owner_id}
                    placeholder="User ID of the tenant owner"
                    class="input input-bordered input-sm"
                    required
                  />
                </div>
                <div class="flex gap-6 items-center">
                  <div class="form-control">
                    <label class="label cursor-pointer justify-start gap-3">
                      <input type="hidden" name="is_removable" value="false" />
                      <input type="checkbox" name="is_removable" value="true" class="checkbox checkbox-sm" checked={@create_is_removable} />
                      <span class="label-text">Removable</span>
                    </label>
                  </div>
                  <div class="form-control">
                    <label class="label cursor-pointer justify-start gap-3">
                      <input type="hidden" name="is_assignable" value="false" />
                      <input type="checkbox" name="is_assignable" value="true" class="checkbox checkbox-sm" checked={@create_is_assignable} />
                      <span class="label-text">Assignable</span>
                    </label>
                  </div>
                </div>
                <div class="md:col-span-2 flex gap-2">
                  <button type="submit" class="btn btn-primary btn-sm">Create</button>
                  <button type="button" phx-click="cancel_create" class="btn btn-ghost btn-sm">Cancel</button>
                </div>
              </form>
            </div>
          </div>
        <% end %>

        <!-- Tenants Table -->
        <div class="card bg-base-100 shadow-xl mt-4">
          <div class="card-body">
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Title</th>
                    <th>Code</th>
                    <th>UUID</th>
                    <th>Removable</th>
                    <th>Assignable</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for tenant <- @tenants do %>
                    <%= if @editing == tenant.tenant_id do %>
                      <tr class="bg-base-200">
                        <td><%= tenant.tenant_id %></td>
                        <td colspan="6">
                          <form phx-submit="update" class="flex items-center gap-3 flex-wrap">
                            <input
                              type="text"
                              name="title"
                              value={@edit_title}
                              class="input input-bordered input-sm w-40"
                              placeholder="Title"
                              required
                            />
                            <input
                              type="text"
                              name="code"
                              value={@edit_code}
                              class="input input-bordered input-sm w-32"
                              placeholder="Code"
                              required
                            />
                            <input
                              type="text"
                              name="owner_id"
                              value={@edit_owner_id}
                              class="input input-bordered input-sm w-24"
                              placeholder="Owner ID"
                            />
                            <label class="label cursor-pointer gap-2">
                              <input type="hidden" name="is_removable" value="false" />
                              <input type="checkbox" name="is_removable" value="true" class="checkbox checkbox-sm" checked={@edit_is_removable} />
                              <span class="label-text text-xs">Removable</span>
                            </label>
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
                        <td><%= tenant.tenant_id %></td>
                        <td><%= tenant.title %></td>
                        <td><code class="text-sm"><%= tenant.code %></code></td>
                        <td><code class="text-xs"><%= tenant.uuid %></code></td>
                        <td>
                          <%= if tenant.is_removable do %>
                            <span class="badge badge-success badge-sm">Yes</span>
                          <% else %>
                            <span class="badge badge-ghost badge-sm">No</span>
                          <% end %>
                        </td>
                        <td>
                          <%= if tenant.is_assignable do %>
                            <span class="badge badge-success badge-sm">Yes</span>
                          <% else %>
                            <span class="badge badge-ghost badge-sm">No</span>
                          <% end %>
                        </td>
                        <td class="flex gap-1">
                          <button phx-click="edit" phx-value-id={tenant.tenant_id} class="btn btn-ghost btn-xs">Edit</button>
                          <button
                            phx-click="delete"
                            phx-value-uuid={tenant.uuid}
                            data-confirm="Are you sure you want to delete this tenant?"
                            class="btn btn-error btn-xs"
                          >
                            Delete
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                  <%= if Enum.empty?(@tenants) do %>
                    <tr>
                      <td colspan="7" class="text-center text-base-content/50 py-8">
                        No tenants found
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <%= if length(@tenants) > 0 do %>
              <div class="text-sm text-base-content/50 mt-4">
                Showing <%= length(@tenants) %> tenants
                <%= if length(@tenants) > 0 do %>
                  (Total: <%= List.first(@tenants).total_items %>)
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
