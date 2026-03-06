defmodule KeenAuthPermissionsTestWeb.AuthEventHandler do
  @moduledoc """
  Shared handler for SSE auth events in LiveViews.

  Classifies events into tiers and updates socket assigns accordingly:
  - `:hard` — sets `auth_blocked`, pushes `auth:hard_block` JS event
  - `:medium` — sets `auth_warning` with a message banner
  - `:soft` / `:unknown` — silently reloads data via the provided reload function
  """

  import Phoenix.LiveView, only: [push_event: 3]
  import Phoenix.Component, only: [assign: 2]

  alias KeenAuthPermissions.EventClassification

  @doc """
  Handle an SSE event in a LiveView.

  `reload_fn` is a 1-arity function that takes a socket and returns
  the socket with refreshed data (e.g. `&load_users/1`).
  """
  def handle_sse_event(socket, event, _payload, reload_fn) do
    tier = EventClassification.classify(event)
    message = EventClassification.message(event)

    case tier do
      :hard ->
        socket
        |> assign(auth_blocked: true)
        |> push_event("auth:hard_block", %{
          message: message,
          clear_url: "/auth/clear"
        })

      :medium ->
        socket
        |> assign(auth_warning: true, auth_warning_message: message)

      _soft_or_unknown ->
        socket
        |> assign(loading: true)
        |> reload_fn.()
    end
  end
end
