using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Mission1937.SDK.Generated;
using Microsoft.Win32.SafeHandles;

namespace Mission1937.Sidecar.Host;

internal sealed record RuntimePoll(
    RuntimeWorldSnapshot Snapshot,
    int SelectedSaveSlot,
    uint WorldAddress);

internal sealed class RuntimeWorldReader : IDisposable
{
    private const int ActorSize = 0x294;
    private readonly Process process;
    private readonly SafeProcessHandle processHandle;
    private readonly long imageBase;
    private readonly Stopwatch clock = Stopwatch.StartNew();

    public RuntimeWorldReader(Process process)
    {
        this.process = process;
        processHandle = OpenProcess(
            0x0010 | 0x0400 | 0x1000,
            false,
            process.Id);
        if (processHandle.IsInvalid)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "无法以只读方式打开 M1937 进程。");
        process.Refresh();
        imageBase = process.MainModule?.BaseAddress.ToInt64()
            ?? throw new InvalidOperationException(
                "无法获取 M1937.exe 映像基址。");
    }

    public Process Process => process;

    public RuntimePoll? Poll()
    {
        if (process.HasExited)
            return null;
        var mission = ReadInt32(
            imageBase + M1937Addresses.CurrentMission);
        var slot = ReadInt32(
            imageBase + M1937Addresses.SelectedSaveSlot);
        var world = ReadUInt32(
            imageBase + M1937Addresses.WorldRoot);
        var actors = new List<RuntimeActorSnapshot>();
        if (world != 0)
        {
            var array = ReadUInt32(world + 0x18L);
            var count = ReadInt32(world + 0x3CL);
            if (array != 0 && count is > 0 and <= 4096)
            {
                var pointers = ReadBytes(array, checked(count * 4));
                for (var index = 0; index < count; ++index)
                {
                    var actorAddress =
                        BitConverter.ToUInt32(pointers, index * 4);
                    if (actorAddress == 0)
                        continue;
                    try
                    {
                        var actor = ReadBytes(actorAddress, ActorSize);
                        actors.Add(new RuntimeActorSnapshot(
                            actorAddress,
                            unchecked((uint)I32(actor, 0x064)),
                            I32(actor, 0x074),
                            I32(actor, 0x0D8),
                            I32(actor, 0x0E0),
                            I32(actor, 0x178),
                            I32(actor, 0x188) != 0,
                            I32(actor, 0x194),
                            I32(actor, 0x250)));
                    }
                    catch (Win32Exception)
                    {
                        // The game may replace an actor between the pointer
                        // array read and the record read. Skip that one
                        // snapshot instead of retaining a stale pointer.
                    }
                }
            }
        }
        return new RuntimePoll(
            new RuntimeWorldSnapshot(
                mission,
                clock.ElapsedMilliseconds,
                actors),
            slot,
            world);
    }

    public string ExecutablePath()
    {
        var capacity = 32768;
        var buffer = new char[capacity];
        if (!QueryFullProcessImageName(
                processHandle, 0, buffer, ref capacity))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "无法读取 M1937.exe 路径。");
        return new string(buffer, 0, capacity);
    }

    public void Dispose() => processHandle.Dispose();

    private int ReadInt32(long address) =>
        BitConverter.ToInt32(ReadBytes(address, 4), 0);

    private uint ReadUInt32(long address) =>
        BitConverter.ToUInt32(ReadBytes(address, 4), 0);

    private byte[] ReadBytes(long address, int count)
    {
        var buffer = new byte[count];
        if (!ReadProcessMemory(
                processHandle,
                new IntPtr(address),
                buffer,
                buffer.Length,
                out var read) ||
            read.ToInt64() != buffer.Length)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                $"无法读取游戏内存 0x{address:X8}。");
        return buffer;
    }

    private static int I32(byte[] bytes, int offset) =>
        BitConverter.ToInt32(bytes, offset);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeProcessHandle OpenProcess(
        int desiredAccess,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
        int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadProcessMemory(
        SafeProcessHandle process,
        IntPtr address,
        [Out] byte[] buffer,
        int size,
        out IntPtr bytesRead);

    [DllImport(
        "kernel32.dll",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(
        SafeProcessHandle process,
        int flags,
        [Out] char[] executableName,
        ref int size);
}
