defmodule Mixcord.Shard do
  @moduledoc false

  alias Mixcord.Constants
  import Mixcord.Shard.Helpers

  @behaviour :websocket_client

  #hide sharding
  def start_link(token, caller) do
    start_link(token, caller, 1)
  end

  #expose sharding
  def start_link(token, caller, shard_num) do
    :crypto.start
    :ssl.start
    state_map = %{
      token: token,
      shard_num: shard_num,
      caller: caller,
      seq: nil,
      reconnect_attempts: 0,
      last_heartbeat: 0,
      last_heartbeat_intervals: [] #TODO: Fill this with 0's
    }
    :websocket_client.start_link(gateway() , __MODULE__, state_map)
  end

  def websocket_handle({:binary, payload}, _state, state_map) do
    payload = :erlang.binary_to_term(payload)
    case Constants.name_from_opcode payload.op do
      "DISPATCH" ->
        #TODO: Task.Async this?
        handle_event(payload, state_map)
      "HELLO" ->
        #TODO: Check for resume
        heartbeat(self, payload.d.heartbeat_interval)
        identify(self)
      "HEARTBEAT_ACK" ->
        heartbeat_intervals = state_map.heartbeat_intervals
          |> List.delete_at(-1)
          |> List.insert_at(0, state_map.last_heartbeat - DateTime.utc_now)
        state_map = %{state_map | last_heartbeat_intervals: heartbeat_intervals}
        :noop
    end

    #TODO: Find somewhere else to do this probably
    {:ok, %{state_map | reconnect_attempts: 0}}
  end

  def websocket_info({:status_update, new_status_json}, _ws_req, state_map) do
    #TODO: Flesh this out - Idle time?
    :websocket_client.cast(self, {:binary, status_update_payload(new_status_json)})
    {:ok, state_map}
  end

  def websocket_info({:heartbeat, interval}, _ws_req, state_map) do
    state_map = %{state_map | last_heartbeat: DateTime.utc_now}
    :websocket_client.cast(self, {:binary, heartbeat_payload(state_map.seq)})
    heartbeat(self, interval)
    {:ok, state_map}
  end

  def websocket_info(:identify, _ws_req, state_map) do
    :websocket_client.cast(self, {:binary, identity_payload(state_map)})
    {:ok, state_map}
  end

  def init(state_map) do
    {:once, state_map}
  end

  def onconnect(_ws_req, state_map) do
    {:ok, state_map}
  end

  def ondisconnect(reason, state_map) do
    if state_map.reconnect_attempts > 2 do
      {:close, reason, state_map}
    else
      :timer.sleep(15_000)
      attempts = state_map.reconnect_attempts + 1
      #TODO: Log these - logger? Don't forget one in websocket_terminate method
      #IO.inspect "RECONNECT ATTEMPT NUMBER #{attempts}"
      {:reconnect, %{state_map | reconnect_attempts: attempts}}
    end
  end

  def websocket_terminate(reason, _ws_req, _state_map) do
    #SO TRIGGERED I CANT GET END EVENT CODES
    #IO.inspect "WS TERMINATED BECAUSE: #{reason}"
    :ok
  end

end