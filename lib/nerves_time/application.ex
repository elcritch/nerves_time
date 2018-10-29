defmodule Nerves.Time.Application do
  @moduledoc false
  require Logger
  use Application

  def start(_type, _args) do
    timestamp_handler = Application.get_env(:nerves_time, :timestamp_handler, Nerves.Time.FileTimeHandler)

    #initialize timestamp handler
    {:ok, state} = apply(timestamp_handler, :init, [])

    children = [
      {Nerves.Time.Ntpd, [timestamp_handler: timestamp_handler, timestamp_state: state]}
    ]

    # Sanity check and adjust the clock
    adjust_clock(timestamp_handler, state)

    opts = [strategy: :one_for_one, name: Nerves.Time.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    {:ok, pid, %{timestamp_handler: timestamp_handler, timestamp_state: state}}
  end

  def stop(%{timestamp_handler: timestamp_handler, timestamp_state: state}) do
    # Update the file that keeps track of the time one last time.
    apply(timestamp_handler, :update, [state])
  end

  defp adjust_clock(timestamp_handler, state) do
    file_time = apply(timestamp_handler, :time, [state])
    now = NaiveDateTime.utc_now()

    case Nerves.Time.SaneTime.derive_time(now, file_time) do
      ^now ->
        # No change to the current time. This means that we either have a
        # real-time clock that sets the time or the default time that was
        # set is better than any knowledge that we have to say that it's
        # wrong.
        :ok

      new_time ->
        set_time(new_time)
    end
  end

  defp set_time(%NaiveDateTime{} = time) do
    string_time = time |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()

    case System.cmd("date", ["-u", "-s", string_time]) do
      {_result, 0} ->
        Logger.info("nerves_time initialized clock to #{string_time} UTC")
        :ok

      {message, code} ->
        Logger.error(
          "nerves_time failed to set date/time to '#{string_time}': #{code} #{inspect(message)}"
        )

        :error
    end
  end
end
