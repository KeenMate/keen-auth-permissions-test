defmodule KeenAuthPermissionsTestWeb.UsersLive do
  use KeenAuthPermissionsTestWeb, :live_view

  alias KeenAuthPermissions.Users
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
       page_title: "Users",
       user: user,
       ctx: ctx,
       search_text: "",
       users: [],
       loading: true,
       error: nil
     )
     |> load_users()}
  end

  @impl true
  def handle_event("search", %{"search" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(search_text: search_text, loading: true)
     |> load_users()}
  end

  defp load_users(socket) do
    %{ctx: ctx, search_text: search_text} = socket.assigns
    search = if search_text == "", do: nil, else: search_text

    users =
      case Users.search(ctx, search, nil, nil, nil, 1, 50, @default_tenant_id) do
        {:ok, users} -> users
        _ -> []
      end

    assign(socket, users: users, loading: false)
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
    <.admin_layout current_page={:users}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">Users</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Users</li>
            </ul>
          </div>
        </div>

        <%= if @error do %>
          <div class="alert alert-error mb-6">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
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
                    placeholder="Search users by name, email..."
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
                    <th>Username</th>
                    <th>Email</th>
                    <th>Display Name</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for user <- @users do %>
                    <tr>
                      <td><%= user.user_id %></td>
                      <td><%= user.username %></td>
                      <td><%= user.email %></td>
                      <td><%= user.display_name %></td>
                      <td>
                        <%= if user.is_active do %>
                          <span class="badge badge-success">Active</span>
                        <% else %>
                          <span class="badge badge-error">Disabled</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                  <%= if Enum.empty?(@users) do %>
                    <tr>
                      <td colspan="5" class="text-center text-base-content/50">
                        No users found
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
