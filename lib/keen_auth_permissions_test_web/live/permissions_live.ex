defmodule KeenAuthPermissionsTestWeb.PermissionsLive do
  use KeenAuthPermissionsTestWeb, :live_view

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
       page_title: "Permissions",
       user: user,
       ctx: ctx,
       search_text: "",
       permissions: [],
       loading: true,
       error: nil
     )
     |> load_permissions()}
  end

  @impl true
  def handle_event("search", %{"search" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(search_text: search_text, loading: true)
     |> load_permissions()}
  end

  defp load_permissions(socket) do
    %{ctx: ctx, search_text: search_text} = socket.assigns
    search = if search_text == "", do: nil, else: search_text

    # Use search/7 for filtering: ctx, search_text, is_assignable, parent_code, page, page_size, tenant_id
    permissions =
      case Permissions.search(ctx, search, nil, nil, 1, 100, @default_tenant_id) do
        {:ok, perms} -> perms
        _ -> []
      end

    assign(socket, permissions: permissions, loading: false)
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

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout current_page={:permissions}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Permissions</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Permissions</li>
            </ul>
          </div>
        </div>

        <%= if @error do %>
          <div class="alert alert-error mb-6">
            <span><%= @error %></span>
          </div>
        <% end %>

        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <form phx-change="search" phx-submit="search" class="mb-4">
              <div class="form-control">
                <div class="input-group">
                  <input
                    type="text"
                    name="search"
                    value={@search_text}
                    placeholder="Search permissions by title, code..."
                    class="input input-bordered w-full max-w-md"
                    phx-debounce="300"
                  />
                  <%= if @loading do %>
                    <span class="btn btn-square loading"></span>
                  <% end %>
                </div>
              </div>
            </form>
          </div>
        </div>

        <div class="card bg-base-100 shadow-xl mt-4">
          <div class="card-body">
            <div class="overflow-x-auto">
              <table class="table table-zebra">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Title</th>
                    <th>Full Code</th>
                    <th>Short Code</th>
                    <th>Assignable</th>
                    <th>Children</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for perm <- @permissions do %>
                    <tr>
                      <td><%= perm.permission_id %></td>
                      <td><%= perm.title %></td>
                      <td><code class="text-sm"><%= perm.full_code %></code></td>
                      <td>
                        <%= if perm.short_code && perm.short_code != "" do %>
                          <code class="text-sm text-primary"><%= perm.short_code %></code>
                        <% else %>
                          <span class="text-base-content/30">-</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if perm.is_assignable do %>
                          <span class="badge badge-success">Yes</span>
                        <% else %>
                          <span class="badge badge-ghost">No</span>
                        <% end %>
                      </td>
                      <td>
                        <%= if perm.has_children do %>
                          <span class="badge badge-info">Has children</span>
                        <% else %>
                          <span class="text-base-content/30">-</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                  <%= if Enum.empty?(@permissions) do %>
                    <tr>
                      <td colspan="6" class="text-center text-base-content/50">
                        No permissions found
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
    </.admin_layout>
    """
  end
end
