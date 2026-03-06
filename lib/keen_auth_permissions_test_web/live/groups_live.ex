defmodule KeenAuthPermissionsTestWeb.GroupsLive do
  use KeenAuthPermissionsTestWeb, :live_view
  require Logger

  alias KeenAuthPermissions.UserGroups
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
       page_title: "Groups",
       user: user,
       ctx: ctx,
       search_text: "",
       groups: [],
       loading: true,
       error: nil
     )
     |> load_groups()}
  end

  @impl true
  def handle_event("search", %{"search" => search_text}, socket) do
    {:noreply,
     socket
     |> assign(search_text: search_text, loading: true)
     |> load_groups()}
  end

  def handle_event("delete_group", %{"group_id" => group_id_str}, socket) do
    %{ctx: ctx} = socket.assigns
    group_id = String.to_integer(group_id_str)

    case UserGroups.delete(ctx, group_id, @default_tenant_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Group deleted")
         |> load_groups()}

      {:error, reason} ->
        Logger.error("Failed to delete group", reason: inspect(reason))
        {:noreply, put_flash(socket, :error, "Failed to delete group: #{inspect(reason)}")}
    end
  end

  defp load_groups(socket) do
    %{ctx: ctx, search_text: search_text} = socket.assigns
    search = if search_text == "", do: nil, else: search_text

    groups =
      case UserGroups.search(ctx, search, nil, nil, nil, 1, 50, @default_tenant_id) do
        {:ok, groups} -> groups
        _ -> []
      end

    assign(socket, groups: groups, loading: false)
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
    <.admin_layout current_page={:groups}>
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">User Groups</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Groups</li>
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
                    placeholder="Search groups by name, code..."
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
                    <th class="w-1">Actions</th>
                    <th>ID</th>
                    <th>Code</th>
                    <th>Title</th>
                    <th>Type</th>
                    <th>Members</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for group <- @groups do %>
                    <tr>
                      <td>
                        <.action_icon
                          icon="hero-trash"
                          color="red"
                          tooltip="Delete group"
                          confirm={"Delete group \"#{group.title}\"? This action cannot be undone."}
                          phx-click="delete_group"
                          phx-value-group_id={group.user_group_id}
                        />
                      </td>
                      <td><%= group.user_group_id %></td>
                      <td><code class="text-sm"><%= group.code %></code></td>
                      <td><a href={"/groups/#{group.user_group_id}"} class="link link-primary"><%= group.title %></a></td>
                      <td>
                        <span class={"badge #{type_badge(group)}"}>
                          <%= group_type_label(group) %>
                        </span>
                      </td>
                      <td><%= group.member_count %></td>
                      <td>
                        <%= if group.is_active do %>
                          <span class="badge badge-success">Active</span>
                        <% else %>
                          <span class="badge badge-error">Disabled</span>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                  <%= if Enum.empty?(@groups) do %>
                    <tr>
                      <td colspan="7" class="text-center text-base-content/50">
                        No groups found
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

  defp type_badge(%{is_external: true}), do: "badge-warning"
  defp type_badge(%{is_system: true}), do: "badge-info"
  defp type_badge(_), do: "badge-primary"

  defp group_type_label(%{is_external: true}), do: "external"
  defp group_type_label(%{is_system: true}), do: "system"
  defp group_type_label(_), do: "internal"
end
