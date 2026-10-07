# How to run and test

Everything below is run from a **Command Prompt** (or PowerShell) in the
`Project1` folder:

```
cd "....(path)\Project1"
```

Build once, after any code change:

```
.\build.bat
```

`Build OK.`

---



# Part A — Test on one laptop

## A1. Does it find the right coins?

```
.\mine.bat 4 30
```

Output:

```
ahmedrageebahsan;47622	0000019b236e7af8a54e17bbf7eacf3245b84f008c9aaa9216f71df67247fe89
```

## A2. Verify a coin by hand

From <http://www.xorbin.com/tools/sha256-hash-calculator> and paste exactly:

```
ahmedrageebahsan;47622
```

It returns:

```
0000019b236e7af8a54e17bbf7eacf3245b84f008c9aaa9216f71df67247fe89
```

## A3. Check the parallelism

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

On this 6-core / 12-thread laptop it
should land around **10–11**. 
The ratio drops if the laptop is hot, if it is on battery saver, or if
something else is using the CPU.

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

## A6. Run forever

Leave off the seconds argument and it mines until you stop it:

```
.\mine.bat 4
```

Press **Ctrl+C** twice to quit.
---

# Part B — Test the distributed code, alone, on one laptop


## B1. Find the IP

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

`192.168.1.124` this can be different.



## B2. Get on the same network


Connect both laptops to the same WIFI.

## B3. On the SERVER laptop only: open the firewall

Right-click **PowerShell** → **Run as Administrator**, then:

```
cd "D:\UF\Saiful courses\DOS\cop6539_DOS\Project1"
powershell -ExecutionPolicy Bypass -File .\allow-firewall.ps1 -SetPrivate
```

The `-SetPrivate` matters. Windows marks most Wi-Fi networks (including
hotspots) as **Public**, and on a Public network it blocks inbound connections
regardless of the rules you add. This laptop's Wi-Fi is currently Public, so
without `-SetPrivate` the worker will never connect.

The script prints the addresses to hand out at the end.


## B4. 2nd laptop needs the project too

On the worker laptop:

1. Install Erlang: `winget install --id Erlang.ErlangOTP -e`
2. Add `C:\Program Files\Erlang OTP\bin` to PATH
3. Download the project
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


## B5. Start the worker

On 2nd laptop:

```
.\mine.bat 192.168.1.124 [IP can be different, see server's log]
```

using whatever address the server printed.

## C5. What proves it worked

1. The server prints `Worker joined: ...`
2. The worker prints **no coins at all**
3. The server's hash rate in the `[Ns]` progress lines rises noticeably
4. The final summary says `Machines: 2` and lists both under `Per machine:`
5. No coin appears twice — the boss is the only source of ranges, so ranges
   handed to the two laptops cannot overlap