defmodule KeenAuthPermissionsTest.Repo do
  use Ecto.Repo,
    otp_app: :keen_auth_permissions_test,
    adapter: Ecto.Adapters.Postgres
end
