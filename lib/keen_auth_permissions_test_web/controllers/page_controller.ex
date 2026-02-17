defmodule KeenAuthPermissionsTestWeb.PageController do
  use KeenAuthPermissionsTestWeb, :controller

  alias KeenAuthPermissions.Auth
  alias KeenAuthPermissions.RequestContext

  def home(conn, _params) do
    user = KeenAuth.current_user(conn)
    render(conn, :home, user: user)
  end

  def login(conn, _params) do
    providers = KeenAuth.list_providers(:keen_auth_permissions_test)
    render(conn, :login, providers: providers)
  end

  def register(conn, _params) do
    render(conn, :register)
  end

  def create_registration(conn, %{"email" => email, "password" => password, "password_confirmation" => password_confirmation, "display_name" => display_name})
      when password == password_confirmation do
    case Auth.register_user(email, password, display_name) do
      {:ok, user} ->
        ctx = RequestContext.system_ctx()
        token_value = generate_token()
        expires_at = DateTime.add(DateTime.utc_now(), 86400, :second)

        case Auth.create_token(ctx, user.user_id, user.uuid, nil, "email_confirmation", "email", token_value, expires_at, nil) do
          {:ok, _token_result} ->
            render(conn, :registration_pending,
              email: email,
              token: token_value
            )

          {:error, _} ->
            conn
            |> put_flash(:warning, "Account created but confirmation token failed. Contact admin.")
            |> redirect(to: "/login")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, format_error(reason))
        |> render(:register)
    end
  end

  def create_registration(conn, %{"password" => password, "password_confirmation" => password_confirmation})
      when password != password_confirmation do
    conn
    |> put_flash(:error, "Passwords do not match")
    |> render(:register)
  end

  def create_registration(conn, _params) do
    conn
    |> put_flash(:error, "Please fill in all required fields")
    |> render(:register)
  end

  def confirm(conn, %{"token" => token}) do
    ctx = RequestContext.system_ctx()

    case Auth.set_token_as_used_by_token(ctx, token, "email_confirmation") do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Email confirmed! You can now sign in.")
        |> redirect(to: "/login")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Confirmation failed: #{format_error(reason)}")
        |> redirect(to: "/login")
    end
  end

  def confirm(conn, _params) do
    conn
    |> put_flash(:error, "Invalid confirmation link")
    |> redirect(to: "/login")
  end

  def dashboard(conn, _params) do
    user = KeenAuth.current_user(conn)
    render(conn, :dashboard, user: user)
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp format_error(%{message: msg}), do: msg
  defp format_error(msg) when is_binary(msg), do: msg
  defp format_error(_), do: "Registration failed. Please try again."
end
