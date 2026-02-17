defmodule KeenAuthPermissionsTest.Auth.Processor do
  @moduledoc """
  Authentication processor that integrates KeenAuth with KeenAuthPermissions.

  This is a simplified processor that works without database integration.
  For production, you would integrate with the database to persist users.
  """

  @behaviour KeenAuth.Processor

  require Logger

  @impl true
  def process(conn, provider, mapped_user, oauth_result) do
    Logger.info("[Processor] Processing authentication for provider: #{inspect(provider)}")
    Logger.debug("[Processor] Mapped user: #{inspect(mapped_user)}")

    # mapped_user can be:
    # - A struct (KeenAuth.User) from OAuth mappers - use dot notation
    # - A plain map with string keys from email handler - use get/2
    user_id = get_field(mapped_user, [:user_id, "sub"])
    email = get_field(mapped_user, [:email, "email"])
    username = get_field(mapped_user, [:username, "preferred_username"]) || email
    display_name = get_field(mapped_user, [:display_name, "name"]) || email

    user = %{
      id: user_id || "demo-user",
      uuid: user_id,
      username: username,
      email: email,
      display_name: display_name,
      roles: get_roles_for_provider(provider),
      permissions: get_permissions_for_provider(provider),
      groups: get_groups_for_provider(provider)
    }

    Logger.info("[Processor] User authenticated: #{user.username}")
    {:ok, conn, user, oauth_result}
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

  @impl true
  def sign_out(conn, provider, params) do
    Logger.info("[Processor] User signing out from #{inspect(provider)}")

    storage = KeenAuth.Storage.current_storage(conn)

    conn
    |> storage.delete()
    |> Phoenix.Controller.redirect(to: params["redirect_to"] || "/")
  end

  # Demo roles based on provider
  defp get_roles_for_provider(provider) when provider in [:entra, :azure_ad, :aad] do
    ["admin", "users"]
  end

  defp get_roles_for_provider(_provider) do
    ["users"]
  end

  # Demo permissions based on provider
  defp get_permissions_for_provider(provider) when provider in [:entra, :azure_ad, :aad] do
    [
      "admin.read",
      "admin.write",
      "users.list",
      "users.read",
      "users.write",
      "groups.list",
      "groups.read",
      "permissions.list"
    ]
  end

  defp get_permissions_for_provider(_provider) do
    ["users.list", "users.read"]
  end

  # Demo groups based on provider
  defp get_groups_for_provider(provider) when provider in [:entra, :azure_ad, :aad] do
    ["admins", "users"]
  end

  defp get_groups_for_provider(_provider) do
    ["users"]
  end
end
