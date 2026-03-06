defmodule KeenAuthPermissionsTestWeb.AuthComponents do
  @moduledoc """
  Function components for auth event UI: hard-block hook anchor and warning banner.
  """

  use Phoenix.Component

  @doc """
  Renders the auth event listener (JS hook anchor) and warning banner.

  Include at the top of every authenticated LiveView's render template:

      <.auth_event_listener
        auth_blocked={@auth_blocked}
        auth_warning={@auth_warning}
        auth_warning_message={@auth_warning_message}
      />
  """
  # ============================================================================
  # Pagination
  # ============================================================================

  @doc """
  Renders a pagination bar with prev/next buttons and page info.

  ## Examples

      <.pagination page={@page} page_size={@page_size} total_items={@total_items} />
  """
  attr :page, :integer, required: true
  attr :page_size, :integer, required: true
  attr :total_items, :integer, required: true

  def pagination(assigns) do
    total_pages = max(1, ceil(assigns.total_items / assigns.page_size))
    from = (assigns.page - 1) * assigns.page_size + 1
    to = min(assigns.page * assigns.page_size, assigns.total_items)

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(:from, from)
      |> assign(:to, to)

    ~H"""
    <div class="flex items-center justify-between mt-4">
      <div class="text-sm text-base-content/50">
        <%= if @total_items > 0 do %>
          Showing <%= @from %>–<%= @to %> of <%= @total_items %>
        <% else %>
          No results
        <% end %>
      </div>
      <%= if @total_pages > 1 do %>
        <div class="join">
          <button
            phx-click="go_to_page"
            phx-value-page={@page - 1}
            class="join-item btn btn-sm"
            disabled={@page <= 1}
          >
            «
          </button>
          <%= for p <- page_range(@page, @total_pages) do %>
            <%= if p == :gap do %>
              <button class="join-item btn btn-sm btn-disabled">…</button>
            <% else %>
              <button
                phx-click="go_to_page"
                phx-value-page={p}
                class={"join-item btn btn-sm #{if p == @page, do: "btn-active", else: ""}"}
              >
                <%= p %>
              </button>
            <% end %>
          <% end %>
          <button
            phx-click="go_to_page"
            phx-value-page={@page + 1}
            class="join-item btn btn-sm"
            disabled={@page >= @total_pages}
          >
            »
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp page_range(current, total) when total <= 7, do: Enum.to_list(1..total)

  defp page_range(current, total) do
    cond do
      current <= 4 ->
        Enum.to_list(1..5) ++ [:gap, total]

      current >= total - 3 ->
        [1, :gap] ++ Enum.to_list((total - 4)..total)

      true ->
        [1, :gap] ++ Enum.to_list((current - 1)..(current + 1)) ++ [:gap, total]
    end
  end

  # ============================================================================
  # Auth Event Listener
  # ============================================================================

  attr :auth_blocked, :boolean, default: false
  attr :auth_warning, :boolean, default: false
  attr :auth_warning_message, :string, default: ""

  def auth_event_listener(assigns) do
    ~H"""
    <%!-- JS hook anchor for hard-block overlay --%>
    <div id="auth-events-hook" phx-hook="AuthEvents" class="hidden"></div>

    <%!-- Medium-tier warning banner --%>
    <%= if @auth_warning do %>
      <div class="fixed top-0 left-0 right-0 z-[9998] flex justify-center p-4 pointer-events-none">
        <div role="alert" class="alert alert-warning shadow-lg max-w-2xl pointer-events-auto">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 shrink-0 stroke-current" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <span><%= @auth_warning_message %></span>
          <div class="flex gap-2">
            <button onclick="window.location.reload()" class="btn btn-sm btn-warning">Reload</button>
            <button phx-click="dismiss_auth_warning" class="btn btn-sm btn-ghost">Dismiss</button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
