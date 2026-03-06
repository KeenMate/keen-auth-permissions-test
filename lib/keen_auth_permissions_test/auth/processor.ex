defmodule KeenAuthPermissionsTest.Auth.Processor do
  @moduledoc """
  Authentication processor for the email strategy.

  Fetches the user from the database and ensures groups/permissions are set,
  returning a `%KeenAuthPermissions.User{}` struct.

  The entra (Azure AD) strategy uses `KeenAuthPermissions.Processor.AzureAD` directly.
  """

  @behaviour KeenAuth.Processor

  require Logger

  alias KeenAuthPermissions.DbContext
  alias KeenAuthPermissions.User

  @impl true
  def process(conn, :email, mapped_user, response) do
    Logger.info("[Processor] Processing email authentication")

    db_context = DbContext.current_db_context!(conn)
    user_id = mapped_user |> get_field([:user_id, "sub"]) |> parse_user_id()

    {:ok, [db_user]} = db_context.auth_get_user_by_id(user_id, nil)

    {groups, permissions} =
      case db_context.auth_ensure_groups_and_permissions(
             "system",
             1,
             "email-login",
             db_user.user_id,
             "email",
             [],
             []
           ) do
        {:ok, [%{groups: groups, short_code_permissions: short_code_permissions}]} ->
          {groups, short_code_permissions}

        {:ok, []} ->
          {[], []}
      end

    user = %User{
      user_id: db_user.user_id,
      code: db_user.code,
      uuid: db_user.uuid,
      username: db_user.username,
      email: db_user.email,
      display_name: db_user.display_name,
      groups: groups,
      permissions: permissions
    }

    Logger.info("[Processor] User authenticated: #{user.username}")
    {:ok, conn, user, response}
  end

  @impl true
  def sign_out(conn, _provider, params) do
    Logger.info("[Processor] User signing out")

    storage = KeenAuth.Storage.current_storage(conn)

    conn
    |> storage.delete()
    |> Phoenix.Controller.redirect(to: params["redirect_to"] || "/")
  end

  # Helper to get a field from either a struct or a map with string keys
  defp get_field(data, keys) when is_list(keys) do
    Enum.find_value(keys, fn key ->
      cond do
        is_struct(data) and is_atom(key) -> Map.get(data, key)
        is_map(data) and is_binary(key) -> Map.get(data, key)
        is_map(data) and is_atom(key) -> Map.get(data, key)
        true -> nil
      end
    end)
  end

  defp parse_user_id(id) when is_integer(id), do: id

  defp parse_user_id(id) when is_binary(id) do
    {int, _} = Integer.parse(id)
    int
  end
end
