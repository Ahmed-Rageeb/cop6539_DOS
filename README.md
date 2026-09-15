# COP6539 / COP5615 — Project 1: Distributed Bitcoin Mining in Erlang

**Team:** Ahmed Rageeb Ahsan (`ahmedrageebahsan`), Saiful Islam (`saiful.islam`)

Coins are strings of the form `ahmedrageebahsan;<N>` whose SHA-256 digest begins with at
least *K* zero hex digits. Everything is built on the actor model: one **boss** actor owns
the search space and hands out disjoint ranges; many **miner** actors grind through those
ranges and report back. There is no shared mutable state, no ETS, no NIF-level threading —
only processes and messages.

---

## 1. Setup

Erlang/OTP is the only dependency.

```
winget install --id Erlang.ErlangOTP -e
```

Then add `C:\Program Files\Erlang OTP\bin` to `PATH`. Verify with `erl -noshell -eval "halt()."`.

Build once:

```
cd Project1
.\build.bat
```

## 2. Running

```
.\mine.bat 4                     server, mining coins with 4 leading zeros, until Ctrl+C
.\mine.bat 4 60                  server, stopping after 60 seconds and printing a summary
.\mine.bat 4 60 192.168.1.7      server, advertising that exact IP to workers
.\mine.bat 10.22.13.155          worker, joining the server at that address
```

Server options may appear in any position: `start=N` begins the search at candidate N
instead of 0, `chunk=N` sets the work-unit size, `miners=N` sets the actor count.

A numeric first argument means "be the server"; anything containing a dot or colon means
"be a worker and go find the server there".

Coins go to **stdout**, one per line, as `input<TAB>hash`. Progress and the summary go to
**stderr**, so `.\mine.bat 4 60 > coins.txt` captures exactly the required output and nothing else.
Workers print no coins at all — the server prints every coin, as the assignment requires.

---

## 3. Size of the work unit

**Chosen work unit: 10,000 candidates per request.**

### How it was determined

`actors:bench()` grinds a fixed 20,000,000 candidates with each chunk size, so every row does
identical work and only the coordination pattern differs. K is set to 12 so no coin is ever
found and the measurement reflects hashing plus boss/miner messaging only.

```
erl -noshell -pa . -eval "actors:bench(), halt()."
```

Representative pass (AMD Ryzen 5 5500U, 6 cores / 12 threads, 12 miner actors):

| Chunk size | Hashes/sec | REAL (s) | CPU (s) | CPU/REAL |
|-----------:|-----------:|---------:|--------:|---------:|
| 100        | 3.27 M     | 6.11     | 41.5    | 6.79     |
| 1,000      | 3.91 M     | 5.12     | 44.6    | 8.72     |
| **10,000** | **4.29 M** | **4.67** | 52.7    | **11.30**|
| 100,000    | 4.28 M     | 4.67     | 52.5    | 11.24    |
| 1,000,000  | 4.07 M     | 4.92     | 48.9    | 9.95     |
| 5,000,000  | 2.34 M     | 8.55     | 32.6    | 3.82     |

* **10,000–100,000** is the flat optimum.

Because 10,000 and 100,000 were within noise of each other on a single pass, and because this
laptop thermally throttles under sustained load (which makes any two passes run minutes apart
non-comparable), the tie was broken with an **alternating A/B** in one process, back to back:

| Round | chunk = 10,000 | chunk = 100,000 |
|------:|---------------:|----------------:|
| 1     | 4.11 M/s (10.76) | 3.99 M/s (10.41) |
| 2     | 4.10 M/s (10.70) | 3.94 M/s (10.18) |

10,000 won every round. It is also the better choice for the distributed case, for two reasons
that the single-machine benchmark cannot show:

* **Load balancing.** A work unit takes one miner ≈ 30 ms. A slower laptop simply requests
  fewer units; nothing has to be predicted or configured in advance. With a 5,000,000-candidate
  unit, a slow machine holding the last unit stalls the whole run.
* **Bounded loss.** If a worker laptop is closed mid-chunk, at most 10,000 candidates are
  wasted rather than millions.

---

## 4. Result of running the program for input 4

```
.\mine.bat 4 60
```

First ten lines of stdout (the full run produced **3,755 coins**; order varies between runs
because 12 miner actors report concurrently):

```
ahmedrageebahsan;63657	00001e0d88b9a8a74d11ea52db0c93decd4ddedcd3c209b9f1ab28356dc583ad
ahmedrageebahsan;47622	0000019b236e7af8a54e17bbf7eacf3245b84f008c9aaa9216f71df67247fe89
ahmedrageebahsan;49341	000027f344c2cd4762ea1a92798688b6d3f9c49ad2c918deec91594298c2d0ee
ahmedrageebahsan;94984	00008a0632d1a528c9f4b36b2ec32c4d591e9deb151d48810bb1643b529e5eed
ahmedrageebahsan;205169	0000faab3afebf9be1db47c7611468db14662c854c0203cf9ef87bdff2d0d2e1
ahmedrageebahsan;198030	0000f58312331c414076f31733dac54947826b0bf5eef2ff08e630dbc86cd3b6
ahmedrageebahsan;292848	000073c5e1622cf02a37f1e64d3aab722f71d355d016eba00e8d0e5654e9a777
ahmedrageebahsan;312169	00008342c9c01f4a3fa4d1fd21e026bd3c094bc7c29c124148d0b9043a1959cb
ahmedrageebahsan;397824	00005287f2f071d798bf250c18f695d151ad585f6f225bcfaf4e11dfd8ca119c
ahmedrageebahsan;480538	0000d25a36270b41b1521e44f93c155ed0bbe5b856c8561463b28d245943bd70
```

`ahmedrageebahsan;47622` is the numerically first coin for K = 4. Verified against
<http://www.xorbin.com/tools/sha256-hash-calculator>:

```
input: ahmedrageebahsan;47622
sha256: 0000019b236e7af8a54e17bbf7eacf3245b84f008c9aaa9216f71df67247fe89
```


---

## 5. Running time and CPU / REAL ratio

Windows has no `times` command, so the program reports the equivalent itself using the BEAM's
own accounting: `statistics(runtime)` (total CPU across all VM threads) and
`statistics(wall_clock)`. The summary is printed at the end of every timed run.

```
===== Mining summary =====
Machines:      1 (this one + 0 worker node(s))
Coins found:   3755
Hashes tried:  242450000
Hash rate:     4.04M hashes/sec
REAL time:     60.001 s
CPU time:      655.922 s
CPU / REAL:    10.93   (cores effectively used on THIS node)
Best coin:     ahmedrageebahsan;147408969  (7 leading zeros)
               0000000bb82cd9d866f47fc207fecb0b3999e0c02a5b161bd6048784abcc1960
==========================
```

### **CPU / REAL = 10.93**

On a 6-core / 12-thread CPU, 10.93 means essentially every hardware thread was busy for the
whole run. The remaining gap from 12.0 is the usual SMT ceiling: two threads on one physical
core do not deliver two cores' worth of throughput on a compute-bound integer workload like
SHA-256.


---

## 6. Coin with the most zeros

| | |
|---|---|
| **Input** | `ahmedrageebahsan;147408969` |
| **SHA-256** | `0000000bb82cd9d866f47fc207fecb0b3999e0c02a5b161bd6048784abcc1960` |
| **Leading zeros** | **7** |

Found during a sustained `.\mine.bat 7 1800` run: 30 minutes, **6,745,370,000 hashes**, which
yielded **35 distinct coins with 7 leading zeros**. Every coin with 7 leading zeros also
satisfies K = 1…6, so the program discovers its own record as a side effect — the boss tracks
the maximum number of leading zeros it has ever been told about, whatever K the run was
launched with.


The full run summary and all 35 coins from the record run are in
[`results/`](results/).

---

## 7. Largest number of machines

**2 machines** (two Windows laptops on the same LAN), with 12 miner actors on each, 24 miner
actors in total, all coordinated by the single boss on the server laptop.

The design has no fixed limit: a worker is anonymous to the boss beyond being the sender of a
`request_work` message, so any number may join or leave at any time while the server keeps
mining. The summary reports each machine's contribution:

```
Machines:      2 (this one + 1 worker node(s))
Hash rate:     4.52M hashes/sec
Per machine:
  boss@192.168.1.124                    125.30M hashes (79.2%)
  worker69189@192.168.1.124              33.00M hashes (20.8%)
```

---


### Files

| File | Role |
|---|---|
| `Project1/project1.erl` | Pure hashing kernel. No processes, no messages. |
| `Project1/actors.erl` | Boss actor, miner actor, worker-node join, benchmark. |
| `Project1/app.erl` | Command line parsing, node naming, distribution bootstrap. |
| `Project1/build.bat` | Compiles the three modules. |
| `Project1/mine.bat` | Runner. |
| `Project1/allow-firewall.ps1` | Opens the ports workers need. Admin, server laptop, once. |

---

## 9. Running across two machines

On the **server** laptop, once, as Administrator:

```
powershell -ExecutionPolicy Bypass -File .\allow-firewall.ps1
```

Then:

```
.\mine.bat 6
```

It prints the address to give the workers:

```
================================================
 SERVER READY -- node 'boss@192.168.1.124'
 Workers should be started with:   mine 192.168.1.124
================================================
```

On the **worker** laptop:

```
.\mine.bat 192.168.1.124
```

The server logs `Worker joined: ...` and its hash rate rises. The worker prints nothing but
diagnostics.


---
