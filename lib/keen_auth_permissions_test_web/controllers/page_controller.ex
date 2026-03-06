defmodule KeenAuthPermissionsTestWeb.PageController do
  use KeenAuthPermissionsTestWeb, :controller

  alias KeenAuthPermissions.Auth
  alias KeenAuthPermissions.Mfa
  alias KeenAuthPermissions.RequestContext
  alias KeenAuthPermissionsTestWeb.ConnContext

  @default_tenant_id 1

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

  def create_registration(conn, %{
        "email" => email,
        "password" => password,
        "password_confirmation" => password_confirmation,
        "display_name" => display_name
      })
      when password == password_confirmation do
    case Auth.register_user(email, password, display_name) do
      {:ok, user} ->
        ctx = RequestContext.service_ctx(:registrator) |> ConnContext.enrich(conn)
        token_value = generate_token()
        expires_at = DateTime.add(DateTime.utc_now(), 86400, :second)

        case Auth.create_token(
               ctx,
               user.user_id,
               user.uuid,
               nil,
               "email_confirmation",
               "email",
               token_value,
               expires_at,
               nil
             ) do
          {:ok, _token_result} ->
            render(conn, :registration_pending,
              email: email,
              token: token_value
            )

          {:error, _} ->
            conn
            |> put_flash(
              :warning,
              "Account created but confirmation token failed. Contact admin."
            )
            |> redirect(to: "/login")
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, format_error(reason))
        |> render(:register)
    end
  end

  def create_registration(conn, %{
        "password" => password,
        "password_confirmation" => password_confirmation
      })
      when password != password_confirmation do
    conn
    |> put_status(:unprocessable_entity)
    |> put_flash(:error, "Passwords do not match")
    |> render(:register)
  end

  def create_registration(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_flash(:error, "Please fill in all required fields")
    |> render(:register)
  end

  def confirm(conn, %{"token" => token}) do
    ctx = RequestContext.service_ctx(:token_manager) |> ConnContext.enrich(conn)

    case Auth.set_token_as_used_by_token(ctx, token, "email_confirmation") do
      {:ok, result} ->
        if mfa_setup_needed?(ctx, result.user_id) do
          conn
          |> put_session(:mfa_setup_user_id, result.user_id)
          |> put_flash(:info, "Email confirmed! Please set up two-factor authentication.")
          |> redirect(to: "/mfa/setup")
        else
          conn
          |> put_flash(:info, "Email confirmed! You can now sign in.")
          |> redirect(to: "/login")
        end

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

    full_permissions =
      KeenAuthPermissions.PermissionsMap.resolve_permissions(user.permissions || [])

    render(conn, :dashboard, user: user, full_permissions: full_permissions)
  end

  defp mfa_setup_needed?(ctx, user_id) do
    with {:ok, true} <- Mfa.is_required?(ctx, user_id, @default_tenant_id),
         {:ok, statuses} <- Mfa.get_status(ctx, user_id) do
      not Enum.any?(statuses, & &1.is_confirmed)
    else
      _ -> false
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp format_error(%{message: msg}), do: msg
  defp format_error(msg) when is_binary(msg), do: msg
  defp format_error(_), do: "Registration failed. Please try again."
end
