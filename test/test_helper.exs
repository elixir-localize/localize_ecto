# Integration tests run against a real PostgreSQL server. Connection
# settings follow the libpq environment variables so CI (service
# container with a password) and local development (trust auth) both
# work without configuration changes.
Application.put_env(:localize_ecto, Localize.Ecto.TestRepo,
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD"),
  database: "localize_ecto_test",
  pool_size: 2,
  log: false
)

repo_config = Application.get_env(:localize_ecto, Localize.Ecto.TestRepo)

case Ecto.Adapters.Postgres.storage_up(repo_config) do
  :ok -> :ok
  {:error, :already_up} -> :ok
  {:error, reason} -> raise "could not create test database: #{inspect(reason)}"
end

{:ok, _} = Localize.Ecto.TestRepo.start_link()

ExUnit.start()
