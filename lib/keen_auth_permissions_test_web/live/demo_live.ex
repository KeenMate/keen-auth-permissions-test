defmodule KeenAuthPermissionsTestWeb.DemoLive do
  use KeenAuthPermissionsTestWeb, :live_view

  alias KeenAuthPermissions.PermissionHelpers
  alias KeenAuthPermissions.User

  @impl true
  def mount(_params, session, socket) do
    user = session["keen_auth_user"]

    # Create a demo User struct for permission checking
    demo_user =
      if user do
        %User{
          user_id: user.id,
          code: nil,
          uuid: user.uuid,
          username: user.username,
          email: user.email,
          display_name: user.display_name,
          groups: user.roles || [],
          permissions: user.permissions || []
        }
      else
        # Demo user for unauthenticated visitors
        %User{
          user_id: 0,
          code: "demo",
          uuid: nil,
          username: "demo",
          email: "demo@example.com",
          display_name: "Demo User",
          groups: ["users", "demo"],
          permissions: ["app.read", "users.list", "reports.view"]
        }
      end

    {:ok,
     assign(socket,
       page_title: "Permission Helpers Demo",
       user: user,
       demo_user: demo_user,
       check_permission: "",
       check_group: "",
       check_result: nil,
       check_type: nil
     )}
  end

  @impl true
  def handle_event("check_permission", %{"permission" => permission}, socket) do
    result = PermissionHelpers.has_any?(socket.assigns.demo_user, permission)

    {:noreply,
     assign(socket,
       check_permission: permission,
       check_result: result,
       check_type: :permission
     )}
  end

  @impl true
  def handle_event("check_group", %{"group" => group}, socket) do
    result = PermissionHelpers.in_any_group?(socket.assigns.demo_user, [group])

    {:noreply,
     assign(socket,
       check_group: group,
       check_result: result,
       check_type: :group
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="navbar bg-base-100 shadow-lg">
        <div class="flex-1">
          <a href="/" class="btn btn-ghost text-xl">KeenAuth Permissions Test</a>
        </div>
        <div class="flex-none gap-2">
          <%= if @user do %>
            <a href="/dashboard" class="btn btn-ghost">Dashboard</a>
            <a href="/events" class="btn btn-ghost">Events</a>
            <a href="/auth/delete" class="btn btn-ghost text-error">Logout</a>
          <% else %>
            <a href="/login" class="btn btn-primary">Login</a>
          <% end %>
        </div>
      </div>

      <div class="container mx-auto p-6">
        <h1 class="text-3xl font-bold mb-6">Permission Helpers Demo</h1>

        <div class="alert alert-info mb-6">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div>
            <p class="font-bold">This demo shows PermissionHelpers in action</p>
            <p>These helpers check permissions in-memory against the User struct, without database calls.</p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <!-- Current User Info -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Demo User</h2>

              <div class="mb-4">
                <p class="text-sm text-base-content/70">Username: <span class="font-mono"><%= @demo_user.username %></span></p>
                <p class="text-sm text-base-content/70">Email: <span class="font-mono"><%= @demo_user.email %></span></p>
              </div>

              <h3 class="font-semibold">Groups</h3>
              <div class="flex flex-wrap gap-2 mb-4">
                <%= for group <- @demo_user.groups do %>
                  <span class="badge badge-primary"><%= group %></span>
                <% end %>
              </div>

              <h3 class="font-semibold">Permissions</h3>
              <div class="flex flex-wrap gap-2">
                <%= for perm <- @demo_user.permissions do %>
                  <span class="badge badge-secondary"><%= perm %></span>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Interactive Checks -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h2 class="card-title">Try It Out</h2>

              <!-- Permission Check -->
              <form phx-submit="check_permission" class="mb-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Check Permission</span>
                  </label>
                  <div class="join">
                    <input
                      type="text"
                      name="permission"
                      value={@check_permission}
                      placeholder="e.g., app.read"
                      class="input input-bordered join-item flex-1"
                    />
                    <button type="submit" class="btn btn-primary join-item">Check</button>
                  </div>
                </div>
              </form>

              <!-- Group Check -->
              <form phx-submit="check_group">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Check Group Membership</span>
                  </label>
                  <div class="join">
                    <input
                      type="text"
                      name="group"
                      value={@check_group}
                      placeholder="e.g., admins"
                      class="input input-bordered join-item flex-1"
                    />
                    <button type="submit" class="btn btn-secondary join-item">Check</button>
                  </div>
                </div>
              </form>

              <!-- Result -->
              <%= if @check_result != nil do %>
                <div class={"alert mt-4 #{if @check_result, do: "alert-success", else: "alert-error"}"}>
                  <%= if @check_type == :permission do %>
                    <span>has_any?("<%= @check_permission %>") = <strong><%= @check_result %></strong></span>
                  <% else %>
                    <span>in_any_group?(["<%= @check_group %>"]) = <strong><%= @check_result %></strong></span>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Code Examples -->
        <div class="card bg-base-100 shadow-xl mt-6">
          <div class="card-body">
            <h2 class="card-title">Usage Examples</h2>

            <div class="mockup-code text-sm">
              <pre data-prefix="$"><code>{"# Boolean checks"}</code></pre>
              <pre data-prefix=">"><code>{"PermissionHelpers.has_any?(user, [\"admin.read\", \"super.admin\"])"}</code></pre>
              <pre data-prefix=">"><code>{"PermissionHelpers.has_all?(user, [\"users.read\", \"users.write\"])"}</code></pre>
              <pre data-prefix=">"><code>{"PermissionHelpers.in_any_group?(user, [\"admins\", \"moderators\"])"}</code></pre>
              <pre data-prefix="$"><code>{"# Result-based checks (for with blocks)"}</code></pre>
              <pre data-prefix=">"><code>{"PermissionHelpers.require_any(user, [\"admin.read\"])"}</code></pre>
              <pre data-prefix=">"><code>{"# Returns {:ok, :authorized} or {:error, %ErrorStruct{}}"}</code></pre>
              <pre data-prefix="$"><code>{"# Function wrappers"}</code></pre>
              <pre data-prefix=">"><code>{"PermissionHelpers.with_permission(user, [\"admin.delete\"], fn -> ... end)"}</code></pre>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
