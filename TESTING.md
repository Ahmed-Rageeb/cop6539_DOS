# How to run and test

Everything below is run from a **Command Prompt** (or PowerShell) in the
`Project1` folder:

```
cd "D:\UF\Saiful courses\DOS\cop6539_DOS\Project1"
```

Build once, after any code change:

```
.\build.bat
```

You should see `Build OK.` If you see `BUILD FAILED`, the error above it tells
you which file and line.

---

## Before you start: make sure nothing else is mining

Only one server can run per machine (they would fight over the node name
`boss`). If you get:

```
ERROR: a node named 'boss' is already running on this machine.
```

then close the other miner's window, or:

```
taskkill /F /IM erl.exe
```

---

# Part A — Test on your own laptop

## A1. Does it find the right coins?

```
.\mine.bat 4 30
```

Mines coins with 4 leading zeros for 30 seconds. You will see a flood of lines
like:

```
ahmedrageebahsan;47622	0000019b236e7af8a54e17bbf7eacf3245b84f008c9aaa9216f71df67247fe89
```

**What to check:** the coin `ahmedrageebahsan;47622` must appear somewhere in
the output. It is the numerically first coin for K = 4. It will *not* be the
first line printed — 12 miner actors run at once and whichever finishes its
chunk first prints first, so the order changes every run. That is expected and
correct.

To find it without scrolling:

```
.\mine.bat 4 30 > coins_k4.txt
findstr 47622 coins_k4.txt
```

## A2. Verify a coin by hand

Go to <http://www.xorbin.com/tools/sha256-hash-calculator> and paste exactly:

```
ahmedrageebahsan;47622
```

It must return:

```
0000019b236e7af8a54e17bbf7eacf3245b84f008c9aaa9216f71df67247fe89
```

Do this for one or two more coins from your own run. This is the check the
assignment explicitly asks for.

You can also confirm the hashing matches the assignment's own example:

```
erl -noshell -pa . -eval "io:format(\"~s~n\",[project1:test_hash(\"COP5615 is a boring class\")]), halt()."
```

must print `fb4431b6a2df71b6cbad961e08fa06ee6fff47e3bc14e977f4b2ea57caee48a4`.

## A3. Check the parallelism (this one is graded)

At the end of the run, look at the summary printed after the coins:

```
===== Mining summary =====
Coins found:   3755
Hashes tried:  242450000
Hash rate:     4.04M hashes/sec
REAL time:     60.001 s
CPU time:      655.922 s
CPU / REAL:    10.93   (cores effectively used on THIS node)
```

**`CPU / REAL` is the graded number.** On this 6-core / 12-thread laptop it
should land around **10–11**. If you ever see a value near 1.0, the actors are
not running in parallel and that loses marks.

The ratio drops if the laptop is hot, if it is on battery saver, or if
something else is using the CPU. For the number you actually report, close
other programs, plug in the charger, and let the machine sit idle for a minute
first.

## A4. Try other zero counts

```
.\mine.bat 1 10
.\mine.bat 2 10
.\mine.bat 3 10
.\mine.bat 6 60
```

Known-correct first coins, if you want to check the output:

| K | Input | Hash starts with |
|---|---|---|
| 1 | `ahmedrageebahsan;0` | `0239c5a9...` |
| 2 | `ahmedrageebahsan;261` | `0066626f...` |
| 3 | `ahmedrageebahsan;5263` | `000faa98...` |
| 4 | `ahmedrageebahsan;47622` | `0000019b...` |
| 6 | `ahmedrageebahsan;3089223` | `00000020...` |

## A5. Reproduce the work-unit benchmark

This is what justifies the chunk size in README section 3. Takes about 40
seconds.

```
erl -noshell -pa . -eval "actors:bench(), halt()."
```

Read the `CPU/REAL` column: it should be lowest at chunk 100, peak around
10,000, and collapse at 5,000,000.

## A6. Run forever

Leave off the seconds argument and it mines until you stop it:

```
.\mine.bat 4
```

Press **Ctrl+C** twice to quit. Note: quitting this way skips the summary, so
use the seconds argument whenever you want the CPU/REAL numbers.

---

# Part B — Test the distributed code, alone, on one laptop

**You can do this today, without your teammate.** It runs two separate Erlang
nodes on one machine — a real server and a real worker talking over real TCP.
It exercises exactly the same code path that two laptops will use.

The only thing it cannot prove is that your network lets two machines reach
each other.

## B1. Find your IP

```
.\mine.bat 4 5
```

Look at the banner it prints:

```
================================================
 SERVER READY -- node 'boss@192.168.1.124'
 Workers should be started with:   mine 192.168.1.124
================================================
```

Note that address. On this laptop it is currently `192.168.1.124`.

## B2. Open TWO Command Prompt windows

Both in `D:\UF\Saiful courses\DOS\cop6539_DOS\Project1`.

**Window 1 — the server:**

```
.\mine.bat 6 120
```

**Window 2 — the worker** (start it a few seconds later):

```
.\mine.bat 192.168.1.124
```

## B3. What you should see

In **window 2** (the worker):

```
Worker 'worker59581@192.168.1.124' connecting to 'boss@192.168.1.124' ...
Connected to 'boss@192.168.1.124'. Mining with 12 miner actors.
Coins are printed by the server, not here. Ctrl+C to stop.
```

**No coins.** That is required by the assignment — workers display nothing, the
server displays everything.

In **window 1** (the server), a new line appears:

```
Worker joined: 'worker59581@192.168.1.124' (12 miner actors)
```

and at the end, a per-machine breakdown:

```
Machines:      2 (this one + 1 worker node(s))
Per machine:
  boss@192.168.1.124                    125.30M hashes (79.2%)
  worker69189@192.168.1.124              33.00M hashes (20.8%)
```

**Do not expect the hash rate to double here.** Both nodes share the same 12
CPU threads, so they split the same machine rather than adding to it. You will
also see `CPU/REAL` *drop*, because it only counts the server VM's own CPU and
the server is now getting half the cores. On two real laptops the rate does
roughly double. The point of this test is that the messaging works, not the
speed.

## B4. Test that failures are handled

**Worker disappears mid-run:** start both as above, then close window 2 (or
Ctrl+C it). Window 1 must keep mining and finish normally.

**Server disappears:** start both, then close window 1. Window 2 must print

```
Server 'boss@192.168.1.124' went down. Stopping miners.
```

and exit on its own, rather than hanging.

**Worker started before the server:** start window 2 first. It retries for
about a minute:

```
  attempt 1/10: no answer, retrying ...
```

Start the server in window 1 within that minute and the worker joins.

**Wrong address:** `.\mine.bat 10.255.255.1` — it should fail with a clear message
after about a minute, not hang.

---

# Part C — Two real laptops

## C0. Get on the same network

Do this first, because it is the step most likely to fail.

**Use a phone hotspot.** University and dorm Wi-Fi very often has *client
isolation* turned on, which stops two laptops from opening a connection to each
other no matter what your firewall says. You cannot fix that from the laptops.
A hotspot has no such restriction.

Connect both laptops to the same hotspot before going further.

## C1. On the SERVER laptop only: open the firewall

Right-click **PowerShell** → **Run as Administrator**, then:

```
cd "D:\UF\Saiful courses\DOS\cop6539_DOS\Project1"
powershell -ExecutionPolicy Bypass -File .\allow-firewall.ps1 -SetPrivate
```

The `-SetPrivate` matters. Windows marks most Wi-Fi networks (including
hotspots) as **Public**, and on a Public network it blocks inbound connections
regardless of the rules you add. This laptop's Wi-Fi is currently Public, so
without `-SetPrivate` the worker will never connect.

The script prints the addresses to hand out at the end. You only need to run it
once per laptop, ever.

To undo it afterwards: `.\allow-firewall.ps1 -Remove`

## C2. Your teammate's laptop needs the project too

On the worker laptop:

1. Install Erlang: `winget install --id Erlang.ErlangOTP -e`
2. Add `C:\Program Files\Erlang OTP\bin` to PATH
3. `git clone https://github.com/Ahmed-Rageeb/cop6539_DOS.git`
4. `cd cop6539_DOS\Project1` then `.\build.bat`

The worker laptop does **not** need the firewall script — it makes the outgoing
connection, it does not accept one.

## C3. Start the server

On the server laptop:

```
.\mine.bat 6 300
```

(K = 6 for a demo — coins appear every few seconds rather than by the thousand,
so the effect of the worker joining is easy to see.)

Read the banner and note the address:

```
 Workers should be started with:   mine 192.168.1.124
```

If that address looks wrong — for example it starts with `172.` and you have
Docker or WSL installed — override it with the third argument:

```
.\mine.bat 6 300 192.168.1.124
```

## C4. Start the worker

On your teammate's laptop:

```
.\mine.bat 192.168.1.124
```

using whatever address the server printed.

## C5. What proves it worked

1. The server prints `Worker joined: ...`
2. The worker prints **no coins at all**
3. The server's hash rate in the `[Ns]` progress lines rises noticeably
4. The final summary says `Machines: 2` and lists both under `Per machine:`
5. No coin appears twice — the boss is the only source of ranges, so ranges
   handed to the two laptops cannot overlap

Save the server's output — the final summary is what goes in README section 7.

## C6. If the worker cannot connect

Work through these in order:

1. **Can they see each other at all?** On the worker laptop:
   `ping 192.168.1.124`
   No reply → it is the network, not the program. Switch to a hotspot.
2. **Is the server actually running?** The name `boss` only exists in epmd
   while a server is up.
3. **Did you run the firewall script with `-SetPrivate`, as Administrator, on
   the server laptop?** Re-run it; it prints the current network category.
4. **Right IP?** A laptop with WSL, Docker, VirtualBox or Hyper-V has several.
   Use the one on the `Wi-Fi` interface. Ignore anything starting `169.254.`
   (those mean "no network").
5. **Both laptops on the same Wi-Fi?** Easy to miss if one silently reconnected
   to eduroam.

---

# Quick reference

| Command | What it does |
|---|---|
| `.\build.bat` | Compile |
| `.\mine.bat 4` | Server, 4 leading zeros, until Ctrl+C |
| `.\mine.bat 4 60` | Server, 60 seconds, then print the summary |
| `.\mine.bat 4 60 192.168.1.7` | Server, forcing the advertised IP |
| `.\mine.bat 192.168.1.124` | Worker joining that server |
| `mine` | Usage help |
| `taskkill /F /IM erl.exe` | Stop everything that is mining |

Coins also accumulate in `Project1\coins.txt` across runs, so nothing is lost
if you close a window. Delete that file when you want a clean slate.

---

# Searching for coins with more zeros

Every run starts at candidate 0 by default, so running `.\mine.bat 7 1800` twice
searches the *same* numbers twice and finds the same coins. To go further,
resume where the previous run stopped — its summary tells you how many hashes
it did:

```
.\mine.bat 7 1800                      first run:  0 .. ~6.7 billion
.\mine.bat 7 2700 start=6745370000     continues from there
```

At roughly 4 M hashes/sec, expect one 7-zero coin per ~66 seconds, one 8-zero
coin per ~18 minutes, and one 9-zero coin per ~4.7 hours. These are averages
over a random process, so a 30-minute run finding no 8-zero coin is ordinary
bad luck rather than a bug.
