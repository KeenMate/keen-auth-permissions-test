defmodule KeenAuthPermissionsTestWeb.ConnContext do
  @moduledoc """
  Helpers for extracting request context metadata from Plug.Conn.

  Demonstrates how consuming apps can enrich RequestContext with conn metadata
  (ip, user_agent, origin) and extra fields (session_id) that flow through
  to the PostgreSQL JSONB context parameter.
  """

  alias KeenAuthPermissions.RequestContext

  @doc """
  Returns keyword opts for ip, user_agent, and origin extracted from conn.

  Use with `Auth.authenticate_by_email/3`:

      Auth.authenticate_by_email(email, password, ConnContext.conn_opts(conn))
  """
  @spec conn_opts(Plug.Conn.t()) :: keyword()
  def conn_opts(%Plug.Conn{} = conn) do
    [
      ip: client_ip(conn),
      user_agent: get_header(conn, "user-agent"),
      origin: get_header(conn, "origin") || get_header(conn, "referer")
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  @doc """
  Enriches a RequestContext with conn metadata and session fields.

  Sets ip, user_agent, origin, and session_id on the context.

      ctx = RequestContext.service_ctx(:registrator)
      ctx = ConnContext.enrich(ctx, conn)
  """
  @spec enrich(RequestContext.t(), Plug.Conn.t()) :: RequestContext.t()
  def enrich(%RequestContext{} = ctx, %Plug.Conn{} = conn) do
    ctx
    |> set_if_present(:ip, client_ip(conn))
    |> set_if_present(:user_agent, get_header(conn, "user-agent"))
    |> set_if_present(:origin, get_header(conn, "origin") || get_header(conn, "referer"))
    |> set_if_present(:session_id, get_session_id(conn))
  end

  defp set_if_present(ctx, _field, nil), do: ctx
  defp set_if_present(ctx, field, value), do: RequestContext.with_field(ctx, field, value)

  defp client_ip(%Plug.Conn{remote_ip: ip}) do
    ip |> :inet.ntoa() |> to_string()
  end

  defp get_header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp get_session_id(conn) do
    Plug.Conn.get_session(conn, :session_id)
  rescue
    # Session may not be available in all contexts
    _ -> nil
  end
end
