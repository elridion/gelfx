defmodule TestHelper.UdpServer do
  @moduledoc false
  use GenServer

  defstruct [
    :socket,
    messages: :queue.new(),
    buffer: %{}
  ]

  def pop(server \\ __MODULE__) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :pop, 1000)
  end

  def all(server \\ __MODULE__) when is_pid(server) or is_atom(server) do
    GenServer.call(server, :all, 1000)
  end

  def init(args) do
    case :gen_udp.open(Keyword.get(args, :port, 22_000), [
           :binary,
           active: true,
           reuseaddr: true
         ]) do
      {:ok, socket} -> {:ok, %__MODULE__{socket: socket}}
      error -> error
    end
  end

  def handle_info({:udp, _socket, _ip, _port_no, _anc, packet}, state) do
    handle_packet(packet, state)
  end

  def handle_info({:udp, _socket, _ip, _port_no, packet}, state) do
    handle_packet(packet, state)
  end

  defp handle_packet(
         <<0x1E, 0x0F, msg_id::bytes-size(8), seq_nr::8, chunk_count::8, chunck::binary>>,
         state
       ) do
    msg_buffer =
      state.buffer
      |> Map.get(msg_id, List.duplicate(nil, chunk_count))
      |> List.replace_at(seq_nr, chunck)

    if Enum.any?(msg_buffer, &is_nil/1) do
      {:noreply, %{state | buffer: Map.put(state.buffer, msg_id, msg_buffer)}}
    else
      msg_buffer
      |> IO.iodata_to_binary()
      |> handle_packet(%{state | buffer: Map.delete(state.buffer, msg_id)})
    end
  end

  defp handle_packet(packet, state) do
    message =
      case Jason.decode(packet) do
        {:ok, json} -> json
        _ -> packet
      end

    {:noreply, %{state | messages: :queue.in(message, state.messages)}}
  end

  def handle_call(:pop, _from, state) do
    case :queue.out(state.messages) do
      {:empty, queue} ->
        {:reply, nil, %{state | messages: queue}}

      {{:value, item}, queue} ->
        {:reply, item, %{state | messages: queue}}
    end
  end

  def handle_call(:all, _from, state) do
    {:reply, :queue.to_list(state.messages), %{state | messages: :queue.new()}}
  end

  def terminate(_, state) do
    if state.socket, do: :gen_udp.close(state.socket)
  end
end
