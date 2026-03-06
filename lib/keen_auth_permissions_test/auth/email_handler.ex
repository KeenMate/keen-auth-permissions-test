defmodule KeenAuthPermissionsTest.Auth.EmailHandler do
  @moduledoc """
  Email authentication handler that verifies credentials against the database.
  """

  @behaviour KeenAuth.EmailAuthenticationHandler

  import Phoenix.Controller

  alias KeenAuthPermissions.Auth
  alias KeenAuthPermissionsTestWeb.ConnContext

  require Logger

  @impl true
  def authenticate(conn, %{"email" => email, "password" => password}) do
    Logger.info("[EmailHandler] Attempting authentication for: #{email}")

    case Auth.authenticate_by_email(email, password, ConnContext.conn_opts(conn)) do
      {:ok, user} ->
        Logger.info("[EmailHandler] Authentication successful for: #{email}")
        # Return raw user map - will be passed to Mapper
        {:ok, %{
          "sub" => to_string(user.user_id),
          "email" => user.email,
          "name" => user.display_name,
          "preferred_username" => user.username
        }}

      {:error, reason} ->
        Logger.warning("[EmailHandler] Authentication failed for #{email}: #{inspect(reason)}")
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_conn, _params) do
    {:error, :missing_credentials}
  end

  @impl true
  def handle_authenticated(conn, user) do
    Logger.info("[EmailHandler] User signed in: #{inspect(user.email)}")
    conn
  end

  @impl true
  def handle_unauthenticated(conn, params, {:error, :invalid_credentials}) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> redirect(to: params["redirect_to"] || "/login")
  end

  def handle_unauthenticated(conn, params, {:error, :missing_credentials}) do
    conn
    |> put_flash(:error, "Please provide email and password")
    |> redirect(to: params["redirect_to"] || "/login")
  end

  def handle_unauthenticated(conn, _params, error) do
    Logger.error("[EmailHandler] Unexpected error: #{inspect(error)}")
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: "/login")
  end
end
