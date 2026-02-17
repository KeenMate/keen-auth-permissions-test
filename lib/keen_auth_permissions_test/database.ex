defmodule KeenAuthPermissionsTest.Database do
  @moduledoc """
  Database context with all stored procedure wrappers.
  """
  use KeenAuthPermissions.Database, repo: KeenAuthPermissionsTest.Repo
end
