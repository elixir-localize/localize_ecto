defmodule Localize.Ecto.Type.TimeZone do
  @moduledoc """
  An `Ecto.Type` for IANA time zone identifiers, validated against the CLDR zone inventory.

  Casting accepts a canonical IANA name ("Australia/Sydney"), any CLDR-known alias ("Australia/NSW"), or a BCP 47 short zone identifier as used by the `-u-tz-` locale keyword ("ausyd"); all of them cast to the canonical IANA name, so the stored value is always canonical. Unknown names fail the cast with a validation message.

      schema "events" do
        field :time_zone, Localize.Ecto.Type.TimeZone
      end

  The canonicalization is also available directly via `canonicalize/1` and `canonicalize!/1` — the latter is used by the `Localize.Ecto.at_time_zone/2` query helper to reject unknown zones before they reach the server.

  """

  use Ecto.Type

  @canonical_key {__MODULE__, :canonical}

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def cast(zone) when is_binary(zone) do
    case canonicalize(zone) do
      {:ok, canonical} -> {:ok, canonical}
      {:error, _exception} -> {:error, message: "is not a known IANA time zone"}
    end
  end

  def cast(_other), do: :error

  @impl Ecto.Type
  def load(zone) when is_binary(zone), do: {:ok, zone}

  @impl Ecto.Type
  def dump(zone) when is_binary(zone), do: {:ok, zone}
  def dump(_other), do: :error

  @doc """
  Canonicalizes a time zone identifier to its canonical IANA name.

  ### Arguments

  * `zone` is a canonical IANA name, a CLDR-known alias, or a BCP 47 short zone identifier.

  ### Returns

  * `{:ok, canonical_name}`, or

  * `{:error, exception}` when the zone is unknown.

  ### Examples

      iex> Localize.Ecto.Type.TimeZone.canonicalize("Australia/Sydney")
      {:ok, "Australia/Sydney"}

      iex> Localize.Ecto.Type.TimeZone.canonicalize("Australia/NSW")
      {:ok, "Australia/Sydney"}

      iex> Localize.Ecto.Type.TimeZone.canonicalize("ausyd")
      {:ok, "Australia/Sydney"}

      iex> {:error, %Localize.UnknownTimezoneError{}} = Localize.Ecto.Type.TimeZone.canonicalize("Mars/Olympus_Mons")

  """
  @spec canonicalize(String.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def canonicalize(zone) when is_binary(zone) do
    case Map.fetch(canonical_map(), zone) do
      {:ok, canonical} ->
        {:ok, canonical}

      :error ->
        case Localize.DateTime.Timezone.validate_short_zone(zone) do
          {:ok, canonical} -> {:ok, canonical}
          {:error, exception} -> {:error, exception}
        end
    end
  end

  @doc """
  Canonicalizes a time zone identifier or raises.

  ### Arguments

  * `zone` is a canonical IANA name, a CLDR-known alias, or a BCP 47 short zone identifier.

  ### Returns

  * The canonical IANA name string.

  ### Examples

      iex> Localize.Ecto.Type.TimeZone.canonicalize!("Australia/NSW")
      "Australia/Sydney"

  """
  @spec canonicalize!(String.t()) :: String.t()
  def canonicalize!(zone) do
    case canonicalize(zone) do
      {:ok, canonical} -> canonical
      {:error, exception} -> raise exception
    end
  end

  # Alias-to-canonical map over the CLDR zone inventory: the first
  # alias of each short zone is the canonical IANA name, every other
  # alias maps to it. Built once and cached — the inventory is fixed
  # for the life of the release.
  defp canonical_map do
    case :persistent_term.get(@canonical_key, nil) do
      nil ->
        map =
          for {_short_zone, %{aliases: [canonical | _rest] = aliases}} <-
                Localize.DateTime.Timezone.timezones(),
              alias_name <- aliases,
              into: %{} do
            {alias_name, canonical}
          end

        :persistent_term.put(@canonical_key, map)
        map

      map ->
        map
    end
  end
end
