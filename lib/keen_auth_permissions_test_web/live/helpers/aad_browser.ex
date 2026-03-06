defmodule KeenAuthPermissionsTestWeb.AadBrowser do
  @moduledoc "Helper functions for browsing AAD groups and users via Microsoft Graph API."

  alias GraphApi.OData
  alias GraphApi.OData.Filter
  alias GraphApi.Schema.User, as: AadUser
  alias GraphApi.Schema.Group, as: AadGroup

  def search_groups(search_text) do
    query =
      OData.new()
      |> OData.select(["id", "displayName", "description", "mailEnabled", "securityEnabled"])
      |> OData.top(20)

    query =
      if String.trim(search_text) != "" do
        OData.filter(
          query,
          Filter.new(AadGroup) |> Filter.where(:display_name, :starts_with, search_text)
        )
      else
        query
      end

    case GraphApi.Groups.list(query: query, as: AadGroup) do
      {:ok, %{"value" => groups}} -> {:ok, groups}
      {:error, _} = error -> error
    end
  end

  def search_users(search_text) do
    query =
      OData.new()
      |> OData.select([
        "id",
        "displayName",
        "mail",
        "userPrincipalName",
        "jobTitle",
        "accountEnabled"
      ])
      |> OData.top(20)

    query =
      if String.trim(search_text) != "" do
        OData.filter(
          query,
          Filter.new(AadUser) |> Filter.where(:display_name, :starts_with, search_text)
        )
      else
        query
      end

    case GraphApi.Users.list(query: query, as: AadUser) do
      {:ok, %{"value" => users}} -> {:ok, users}
      {:error, _} = error -> error
    end
  end
end
