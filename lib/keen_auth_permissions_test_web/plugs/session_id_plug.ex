defmodule KeenAuthPermissionsTestWeb.Plugs.SessionId do
  @moduledoc """
  Assigns a unique session_id to each browser session.

  This demonstrates how extra context fields flow through RequestContext
  into the PostgreSQL JSONB context parameter, giving you per-session
  traceability in the audit trail.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :session_id) do
      nil ->
        session_id = "sess-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
        put_session(conn, :session_id, session_id)

      _existing ->
        conn
    end
  end
end
