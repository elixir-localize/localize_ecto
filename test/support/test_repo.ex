defmodule Localize.Ecto.TestRepo do
  @moduledoc false

  use Ecto.Repo, otp_app: :localize_ecto, adapter: Ecto.Adapters.Postgres
end
