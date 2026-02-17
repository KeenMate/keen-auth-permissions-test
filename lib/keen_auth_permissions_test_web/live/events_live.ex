defmodule KeenAuthPermissionsTestWeb.EventsLive do
  use KeenAuthPermissionsTestWeb, :live_view

  require Logger

  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissions.User

  @impl true
  def mount(_params, session, socket) do
    user = session["keen_auth_user"]
    ctx = build_context(user)

    {:ok,
     socket
     |> assign(
       page_title: "User Events",
       user: user,
       ctx: ctx,
       events: [],
       loading: true,
       error: nil,
       # Filters
       event_type: "",
       target_user_id: "",
       from_date: nil,
       to_date: nil,
       page: 1,
       page_size: 50
     )
     |> load_events()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(
       event_type: params["event_type"] || "",
       target_user_id: params["target_user_id"] || "",
       from_date: parse_date(params["from_date"]),
       to_date: parse_date(params["to_date"]),
       page: 1,
       loading: true
     )
     |> load_events()}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(
       event_type: "",
       target_user_id: "",
       from_date: nil,
       to_date: nil,
       page: 1,
       loading: true
     )
     |> load_events()}
  end

  defp load_events(socket) do
    %{ctx: ctx, event_type: event_type, target_user_id: target_user_id,
      from_date: from_date, to_date: to_date, page: page, page_size: page_size} = socket.assigns

    db_context = KeenAuthPermissions.DbContext.get_global_db_context()

    event_type_filter = if event_type == "", do: nil, else: event_type
    target_user_filter = parse_int(target_user_id)

    case db_context.auth_search_user_events(
      ctx.user_id,
      ctx.request_id || "events-search",
      event_type_filter,
      target_user_filter,
      from_date,
      to_date,
      page,
      page_size
    ) do
      {:ok, events} ->
        assign(socket, events: events, loading: false, error: nil)

      {:error, reason} ->
        Logger.error("Failed to load user events",
          reason: inspect(reason),
          user_id: ctx.user_id
        )
        assign(socket, events: [], loading: false, error: "Failed to load events: #{inspect(reason)}")
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

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(date_string) do
    case DateTime.from_iso8601(date_string <> "T00:00:00Z") do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
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
          <a href="/dashboard" class="btn btn-ghost">Dashboard</a>
          <a href="/events" class="btn btn-ghost">Events</a>
          <a href="/auth/delete" class="btn btn-ghost text-error">Logout</a>
        </div>
      </div>

      <div class="container mx-auto p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl font-bold">User Events</h1>
          <div class="breadcrumbs text-sm">
            <ul>
              <li><a href="/">Home</a></li>
              <li><a href="/dashboard">Dashboard</a></li>
              <li>Events</li>
            </ul>
          </div>
        </div>

        <%= if @error do %>
          <div class="alert alert-error mb-6">
            <span><%= @error %></span>
          </div>
        <% end %>

        <!-- Filters Card -->
        <div class="card bg-base-100 shadow-xl mb-4">
          <div class="card-body">
            <h2 class="card-title text-lg mb-4">Filters</h2>
            <form phx-change="filter" phx-submit="filter" class="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div class="form-control">
                <label class="label">
                  <span class="label-text">Event Type</span>
                </label>
                <input
                  type="text"
                  name="event_type"
                  value={@event_type}
                  placeholder="e.g. user_logged_in"
                  class="input input-bordered input-sm"
                  phx-debounce="300"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">Target User ID</span>
                </label>
                <input
                  type="text"
                  name="target_user_id"
                  value={@target_user_id}
                  placeholder="User ID"
                  class="input input-bordered input-sm"
                  phx-debounce="300"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">From Date</span>
                </label>
                <input
                  type="date"
                  name="from_date"
                  value={format_date(@from_date)}
                  class="input input-bordered input-sm"
                />
              </div>

              <div class="form-control">
                <label class="label">
                  <span class="label-text">To Date</span>
                </label>
                <input
                  type="date"
                  name="to_date"
                  value={format_date(@to_date)}
                  class="input input-bordered input-sm"
                />
              </div>

              <div class="md:col-span-4 flex gap-2">
                <button type="button" phx-click="clear_filters" class="btn btn-ghost btn-sm">
                  Clear Filters
                </button>
                <%= if @loading do %>
                  <span class="loading loading-spinner loading-sm"></span>
                <% end %>
              </div>
            </form>
          </div>
        </div>

        <!-- Events Table -->
        <div class="card bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="overflow-x-auto">
              <table class="table table-zebra table-sm">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Event Type</th>
                    <th>Target User</th>
                    <th>Requester</th>
                    <th>IP Address</th>
                    <th>Created At</th>
                    <th>Details</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for event <- @events do %>
                    <tr>
                      <td><%= event.user_event_id %></td>
                      <td>
                        <span class={"badge badge-sm #{event_badge(event.event_type_code)}"}>
                          <%= event.event_type_code %>
                        </span>
                      </td>
                      <td>
                        <div class="flex flex-col">
                          <span class="font-medium"><%= event.target_username || "-" %></span>
                          <span class="text-xs text-base-content/50">ID: <%= event.target_user_id || "-" %></span>
                        </div>
                      </td>
                      <td>
                        <div class="flex flex-col">
                          <span><%= event.requester_username || "-" %></span>
                          <span class="text-xs text-base-content/50">ID: <%= event.requester_user_id || "-" %></span>
                        </div>
                      </td>
                      <td>
                        <span class="text-xs font-mono"><%= event.ip_address || "-" %></span>
                      </td>
                      <td>
                        <span class="text-xs"><%= format_datetime(event.created_at) %></span>
                      </td>
                      <td>
                        <%= if event.event_data && event.event_data != %{} do %>
                          <button class="btn btn-ghost btn-xs" onclick={"modal_#{event.user_event_id}.showModal()"}>
                            View
                          </button>
                          <dialog id={"modal_#{event.user_event_id}"} class="modal">
                            <div class="modal-box">
                              <h3 class="font-bold text-lg">Event Details</h3>
                              <pre class="bg-base-200 p-4 rounded-lg mt-4 text-xs overflow-auto max-h-96"><%= Jason.encode!(event.event_data, pretty: true) %></pre>
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
                      <td colspan="7" class="text-center text-base-content/50 py-8">
                        No events found
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <%= if length(@events) > 0 do %>
              <div class="text-sm text-base-content/50 mt-4">
                Showing <%= length(@events) %> events
                <%= if length(@events) > 0 do %>
                  (Total: <%= List.first(@events).total_items %>)
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp event_badge(type) when type in ["user_logged_in", "user_registered"], do: "badge-success"
  defp event_badge(type) when type in ["user_login_failed"], do: "badge-error"
  defp event_badge(type) when type in ["user_locked", "user_disabled"], do: "badge-warning"
  defp event_badge(_), do: "badge-ghost"

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_date(nil), do: ""
  defp format_date(dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end
end
