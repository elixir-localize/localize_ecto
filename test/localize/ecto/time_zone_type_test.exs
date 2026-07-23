defmodule Localize.Ecto.Type.TimeZoneTest do
  use ExUnit.Case, async: true

  alias Localize.Ecto.Type.TimeZone

  doctest Localize.Ecto.Type.TimeZone

  describe "cast/1" do
    test "accepts a canonical IANA name" do
      assert TimeZone.cast("Australia/Sydney") == {:ok, "Australia/Sydney"}
    end

    test "canonicalizes an alias" do
      assert TimeZone.cast("Australia/NSW") == {:ok, "Australia/Sydney"}
      assert TimeZone.cast("US/Eastern") == {:ok, "America/New_York"}
    end

    test "canonicalizes a BCP 47 short zone identifier" do
      assert TimeZone.cast("ausyd") == {:ok, "Australia/Sydney"}
    end

    test "rejects an unknown zone with a message" do
      assert {:error, message: "is not a known IANA time zone"} =
               TimeZone.cast("Mars/Olympus_Mons")
    end

    test "rejects non-strings" do
      assert TimeZone.cast(42) == :error
      assert TimeZone.cast(nil) == :error
    end
  end

  describe "dump/1 and load/1" do
    test "pass strings through" do
      assert TimeZone.dump("Australia/Sydney") == {:ok, "Australia/Sydney"}
      assert TimeZone.load("Australia/Sydney") == {:ok, "Australia/Sydney"}
      assert TimeZone.dump(42) == :error
    end
  end

  describe "changeset integration" do
    defmodule Event do
      use Ecto.Schema

      embedded_schema do
        field :time_zone, Localize.Ecto.Type.TimeZone
      end
    end

    test "casts and canonicalizes through a changeset" do
      changeset = Ecto.Changeset.cast(%Event{}, %{time_zone: "Australia/NSW"}, [:time_zone])
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :time_zone) == "Australia/Sydney"
    end

    test "an unknown zone is a changeset error" do
      changeset = Ecto.Changeset.cast(%Event{}, %{time_zone: "Nowhere/Void"}, [:time_zone])
      refute changeset.valid?
      assert {"is not a known IANA time zone", _} = changeset.errors[:time_zone]
    end
  end
end
