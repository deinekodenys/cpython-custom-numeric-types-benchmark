# Campaigns 1 to 3 report · Звіт кампаній 1 до 3

[English](#english) · [Українська](#українська)

## English

This document describes how campaigns 1, 2 and 3 were carried out under their protocol,
[`PROTOCOL.md`](PROTOCOL.md): what was done as specified, what was done differently, and what was
not done, with the reasons. It also gives the results of the campaigns, their use and the analyses
made after the data.

Campaigns 1, 2 and 3 are superseded. None of them is the campaign reported in the article, and no
number published in the article comes from them. They are kept for the two uses described below.

### Files

| File | Content |
|---|---|
| `campaign-1/campaign.json` | raw results of 18 runs, run design, environment before and after |
| `campaign-1/pilot.pinned.json`, `campaign-1/pilot.free.json` | pinning pilot, six runs each |
| `campaign-2/campaign.json` | raw results of 18 runs |
| `campaign-2/pilot.pinned.json`, `campaign-2/pilot.free.json` | pinning pilot |
| `campaign-3/campaign.json` | raw results of 18 runs |
| `campaign-3/pilot.pinned.json`, `campaign-3/pilot.free.json` | pinning pilot |

The three campaigns ran under one edition of the protocol and one state of the code. The
`protocol_md5` field and the source checksums in `env_before.build.sources` agree across the three
files, as does the checksum of the built `probe_full` module. What differed between them is the
state of the machine.

The code that produced them is not the code in the repository root:

| File | md5 |
|---|---|
| `probe.c` | `3a29bd9104bb86d46f984a1cbefac30c` |
| `measure.py` | `8999a99b14cad6623d3177d807f76242` |
| `runner.py` | `0b2d962c2a772393ea61715550353ec8` |

### Why they were superseded

One defect is common to all three and was found after campaign 3 had finished.

The hot path of the representatives contained no reference-count operation. With `Py_LIMITED_API`
set to `0x030C0000` or higher, `Py_INCREF` and `Py_DECREF` become calls into the interpreter, and
that is the mechanism through which the two levels of intervention can differ in cost. With no
reference-count operation on the hot path, both builds executed the same code there, so the estimate
for the level of intervention of these campaigns compared two builds and not two levels. The
deallocators also did not release the reference to the heap type that the type gains on every
instance creation, which departs from the documented `tp_dealloc` contract.

Campaigns 1 and 2 were each superseded for a further reason of their own. In both cases the reason
was named before the rerun that replaced them, not after its numbers were seen.

Campaign 1 ran with the `ondemand` governor and the boost lever on, and the recorded frequencies
moved between 1.30 and 2.06 GHz. Three runs out of eighteen carry a disturbed measurement.

Campaign 2 ran with the governor fixed, but a browser was left running. The load average before the
runs was 1.12 to 1.27, against 0.36 to 0.71 in campaign 3.

Campaign 3 was superseded by the common defect alone. Until that defect was found it was the
campaign of the article, and it had been declared as such before it was run.

### Execution

#### Done as specified

All three campaigns measured the six cases of section 1; classes 1 and 2 were not measured.

All three made eighteen runs, each in a separate process, with 300000 iterations and seven
repetitions per case. The design passed the balance checks recorded in each file: each row of the
square is a permutation of the six cases, each case occupies each position once per square, and all
30 ordered pairs of adjacent cases occur, so carryover is balanced. The row shuffle seeds are
1787680562, 1787691521 and 1787692683.

The empty loop was measured at the start and at the end of every run in all three campaigns.

Rules 1 to 5 are implemented in `runner.py`. No run in any of the three campaigns met an exclusion
criterion of rule 6: pinning succeeded in every run, and the load average changed within a run by at
most 0.04, 0.02 and 0.11 respectively.

Every run was pinned to core 3, and the affinity read back after pinning matches in all runs of all
three campaigns. Each campaign was preceded by its pilot of six pinned and six unpinned runs.

The environment was recorded before and after each campaign. The representatives were built in a
separate step before the first run, and the build check passed in all three.

#### Done differently

In campaign 2 the pilot gave a spread of the baseline of 193.6% with pinning against 18.6% without.
Under rule 5 of section 5 that outcome fixes the pinning decision, and it pointed against pinning.
Pinning was kept nonetheless, on the ground that the inversion is attributable to the extraneous
load of that session rather than to pinning itself. This is a departure from the protocol and is
recorded as such. In campaigns 1 and 3 the pilot pointed the other way, with 11.1% against 256.2%
and 13.1% against 71.0%.

#### Not done

The following are departures from the measurement methodology rather than from the protocol, which
section 7 anticipates.

Frequencies were not fixed in campaign 1, which ran on the `ondemand` governor with the boost lever
on. In campaigns 2 and 3 the governor was `performance` and the boost lever was off, but the lever
was accepted by the driver and not by the hardware, so the frequency under load was not held at the
declared maximum.

SMT was on in all three campaigns. `PYTHONHASHSEED` was not fixed. No control platform was
available, so the ratios to the baseline need to be measured again.

Two related points are not deviations. The protocol requires pinning the process, not isolating the
core from the scheduler, so other tasks scheduled on the same core remain a source of disturbance
within the measurement conditions. The environment records the frequency as snapshots at capture
time rather than per case, so the constancy of the frequency within a run relies on the frequency
being fixed, which in campaign 1 it was not.

#### Observations

Runs are numbered from zero by the `seq` field, which is not the numbering the script prints on
screen.

The median of the thirty-six measurements of the empty loop is 30.70 ns in campaign 1, 31.64 ns in
campaign 2 and 30.66 ns in campaign 3. Individual measurements range from 28.51 to 50.77 ns, from
29.04 to 52.74 ns and from 28.40 to 51.06 ns respectively. The drift within a run has a median near
zero in all three but reaches +21.29, −21.48 and +21.63 ns.

Some runs carry a disturbed measurement of the baseline or of the empty loop. A run is called
disturbed here when one of its two empty-loop measurements, or its baseline, departs from the median
of its own campaign by more than 40%. This threshold was chosen after the data and is not a rule of
the protocol; it serves only to name the runs discussed below.

| Campaign | Runs | What departs |
|---|---|---|
| 1 | 1, 5, 15 | run 1, final empty loop 50.32 ns and base 10.47 ns; run 5, final empty loop 50.77 ns and base 10.35 ns; run 15, base 40.78 ns |
| 2 | 16 | initial empty loop 52.74 ns and base 10.86 ns |
| 3 | 7, 11, 17 | run 7, final empty loop 51.06 ns; run 11, initial empty loop 46.62 ns; run 17, base 44.16 ns |

The base medians against which these departures are measured are 21.62, 22.14 and 21.33 ns. None of
these runs meets either criterion of rule 6, so all were kept in the primary analysis of their own
campaign. The cause has not been established.

The two kinds of disturbance do not affect the analysis in the same way. A disturbed baseline
distorts every ratio of its run, because the base is the denominator, but leaves the within-run
contrasts of rule 3 untouched, because the base does not enter them. A disturbed empty loop distorts
both, because it is subtracted from every case additively and does not cancel in a log ratio. In
campaign 3, replacing the empty loop of run 7 by the typical value moves the state placement
estimate of that run from +21.4% to +16.6%, while the same substitution in run 17 moves it from
+23.9% to +24.2%.

### Primary results

These are the results the three campaigns produced under their own protocol. They are superseded and
are shown so that the record is complete.

Ratios to the baseline, computed within each run (rule 2), as medians with their range:

| Class | Campaign 1 | Campaign 2 | Campaign 3 |
|---|---|---|---|
| 3 | 1.884 (1.074 to 3.114) | 1.944 (1.808 to 2.882) | 1.993 (0.982 to 2.553) |
| 4 | 1.917 (1.059 to 4.693) | 1.937 (1.740 to 2.983) | 1.978 (0.964 to 2.664) |
| 5 | 2.275 (1.268 to 3.764) | 2.415 (2.087 to 3.686) | 2.361 (1.234 to 3.211) |
| 6 | 21.033 (10.909 to 44.072) | 21.369 (18.726 to 44.062) | 21.542 (10.214 to 33.742) |
| 7 | 2.278 (1.222 to 3.720) | 2.339 (2.002 to 3.600) | 2.327 (1.178 to 3.199) |

Axis effects (rules 3 and 4), as medians of within-run differences with 95% bootstrap intervals:

| Quantity | Campaign 1 | Campaign 2 | Campaign 3 |
|---|---|---|---|
| state placement, public C API, 3 → 5 | +19.8% [+16.6, +22.6] | +23.4% [+19.0, +28.5] | +20.0% [+16.9, +25.0] |
| state placement, limited API, 4 → 7 | +17.4% [+15.9, +22.5] | +20.5% [+16.2, +21.8] | +20.1% [+16.0, +21.9] |
| level of intervention, in-object, 4 → 3 | −0.0% [−1.0, +1.8] | +1.4% [−1.6, +3.3] | +1.0% [−1.3, +1.7] |
| level of intervention, table, 7 → 5 | +1.0% [−0.6, +2.6] | +3.6% [+1.7, +4.4] | +1.3% [+0.2, +2.9] |
| main effect of state placement | +18.1% [+15.9, +24.4] | +22.1% [+17.3, +23.5] | +20.7% [+16.8, +22.1] |
| main effect of level of intervention | +0.8% [−0.6, +1.7] | +2.6% [+1.2, +2.9] | +1.2% [−0.5, +2.1] |
| interaction | +0.9% [−3.7, +3.5] | +1.9% [−0.0, +6.4] | +1.7% [−0.6, +3.9] |

Under rule 4 the state placement effect is present in all three campaigns and is reported as a
single value, since the interval of the interaction includes zero. The effect of the level of
intervention is not established in campaigns 1 and 3 and is present in campaign 2. The section on
use explains why the column of the level of intervention of these campaigns does not measure a
difference between levels.

Position effect (rule 5), as the change per position:

| Case | Campaign 1 | Campaign 2 | Campaign 3 |
|---|---|---|---|
| base | +0.24% | −2.88% | −4.45% |
| class 3 | +3.16% | −0.34% | −1.25% |
| class 4 | +3.23% | +1.18% | +1.15% |
| class 5 | −0.32% | +1.70% | +2.88% |
| class 6 | −1.04% | −0.51% | +0.16% |
| class 7 | −0.96% | −0.05% | −1.08% |

### Use

**Robustness of the direction of the state placement effect.** The effect is estimated in nine
independent sets. In every one the point estimate is positive, between +15.0% and +23.8%, and it
excludes zero in seven of the nine. The two that do not are six-run pilots with correspondingly wide
intervals. The common defect concerns the axis of the level of intervention and not this one.

| Set | n | State placement | Level of intervention |
|---|---|---|---|
| campaign 1 | 18 | +18.1% [+15.9, +24.4] | +0.8% [−0.6, +1.7] |
| campaign 2 | 18 | +22.1% [+17.3, +23.5] | +2.6% [+1.2, +2.9] |
| campaign 3 | 18 | +20.7% [+16.8, +22.1] | +1.2% [−0.5, +2.1] |
| pilot 1 pinned | 6 | +22.0% [+16.7, +26.9] | +4.0% [−0.7, +6.8] |
| pilot 1 free | 6 | +23.8% [+18.6, +27.3] | +5.3% [−4.4, +13.6] |
| pilot 2 pinned | 6 | +15.0% [−3.2, +22.5] | −0.1% [−18.9, +2.8] |
| pilot 2 free | 6 | +20.2% [+16.5, +35.8] | +1.2% [−0.6, +13.0] |
| pilot 3 pinned | 6 | +18.4% [−4.0, +23.1] | +1.5% [+0.2, +3.6] |
| pilot 3 free | 6 | +23.4% [+18.1, +32.2] | +3.5% [+0.7, +6.9] |

**An A/A control on the axis of the level of intervention.** The hot paths of the two builds were
identical, so the true difference between the levels in these data is zero by construction. Any
nonzero estimate in the right-hand column measures the bias of the procedure itself, chiefly the
difference in code layout between two separately compiled modules.

Across the nine sets that estimate runs from −0.1% to +5.3%. It is positive in eight of the nine,
and its interval excludes zero in three. A single set does not show this rate.

The bound was obtained after the data and is not part of the protocol. It characterizes the
procedure as it stood in these campaigns, with SMT on and with no alignment requirement on the hot
functions of the two builds, and does not transfer to a procedure that differs in those respects.

### Post hoc analyses

The following were made after the data had been collected. They are not part of the protocol and do
not change the verdicts of rule 4.

#### Sensitivity analysis

Without runs 7, 11 and 17, campaign 3 gives a state placement effect of +20.1% (+16.1% to +21.4%)
and an effect of the level of intervention of +1.0% (−0.7% to +2.1%). Removing three runs breaks the
balance of the three replicates of the Williams design, so this is an estimate of the influence of
the disturbed runs, not a primary result.

#### Tier gap

Class 6 is outside the criterion fixed in advance. Dividing its median ratio by those of the C
classes gives a gap of 9.23 to 11.16 times in campaign 1, 8.85 to 11.03 in campaign 2, and 9.12 to
10.89 in campaign 3.

### Reproduction

The analysis reproduces from the repository root:

```text
python3 runner.py --analyze data/campaigns-1-3/campaign-1/campaign.json
```

The analysis reads the raw data only and does not touch `probe.c` or `measure.py`. If the analysis
code in the root has changed since these campaigns, the medians still reproduce, being
deterministic, while the ends of the bootstrap intervals depend on the seed of that code.

Re-running the measurement does not reproduce from the root, because the representatives in the root
differ from these. Re-running requires the three files identified by checksum above.

---

## Українська

Цей документ описує, як кампанії 1, 2 і 3 виконано за їхнім протоколом,
[`PROTOCOL.md`](PROTOCOL.md): що зроблено за протоколом, що інакше і що не зроблено, з причинами.
Він також подає результати кампаній, їхнє застосування та аналізи, виконані після отримання даних.

Кампанії 1, 2 і 3 заміщені. Жодна з них не є кампанією статті, і жодне опубліковане в статті число
з них не походить. Вони збережені задля двох застосувань, описаних нижче.

### Файли

| Файл | Вміст |
|---|---|
| `campaign-1/campaign.json` | сирі результати 18 прогонів, план прогонів, середовище до і після |
| `campaign-1/pilot.pinned.json`, `campaign-1/pilot.free.json` | пілотне дослідження прив'язки, по шість прогонів |
| `campaign-2/campaign.json` | сирі результати 18 прогонів |
| `campaign-2/pilot.pinned.json`, `campaign-2/pilot.free.json` | пілотне дослідження прив'язки |
| `campaign-3/campaign.json` | сирі результати 18 прогонів |
| `campaign-3/pilot.pinned.json`, `campaign-3/pilot.free.json` | пілотне дослідження прив'язки |

Три кампанії йшли за однією редакцією протоколу і за одним станом коду. Поле `protocol_md5` і
контрольні суми джерел у `env_before.build.sources` збігаються в трьох файлах, і так само
збігається контрольна сума зібраного модуля `probe_full`. Різнився між ними стан машини.

Код, який їх дав, не є кодом у корені репозиторію:

| Файл | md5 |
|---|---|
| `probe.c` | `3a29bd9104bb86d46f984a1cbefac30c` |
| `measure.py` | `8999a99b14cad6623d3177d807f76242` |
| `runner.py` | `0b2d962c2a772393ea61715550353ec8` |

### Чому вони заміщені

Одна вада спільна для всіх трьох і знайдена після завершення кампанії 3.

Вимірюваний код представників не містив жодної операції над лічильником посилань. За
`Py_LIMITED_API` на рівні `0x030C0000` або вище `Py_INCREF` і `Py_DECREF` стають викликами в
інтерпретатор, і саме це є механізмом, через який два щаблі втручання можуть різнитися вартістю. Без
операції над лічильником у вимірюваному коді обидві збірки виконували однаковий код, тож оцінка
рівня втручання в цих кампаніях порівнювала дві збірки, а не два щаблі. Деалокатори також не
віддавали посилання на тип у купі, яке тип отримує на кожному створенні примірника, що відступає від
задокументованого контракту `tp_dealloc`.

Кампанії 1 і 2 заміщені додатково кожна зі своєї причини. В обох випадках причина названа до
перепрогону, який їх замінив, а не після перегляду його чисел.

Кампанія 1 йшла з регулятором частоти `ondemand` і ввімкненим важелем прискорення, а записані
частоти рухалися між 1,30 і 2,06 ГГц. Три прогони з вісімнадцяти несуть збій виміру.

Кампанія 2 йшла із зафіксованим регулятором частоти, але з відкритим браузером. Середнє навантаження
перед прогонами становило від 1,12 до 1,27 проти від 0,36 до 0,71 у кампанії 3.

Кампанія 3 заміщена самою лише спільною вадою. Доки ту ваду не знайшли, кампанія 3 була кампанією
статті і була оголошена такою до свого запуску.

### Виконання

#### Зроблено за протоколом

Усі три кампанії виміряли шість випадків розділу 1, класи 1 і 2 не вимірювалися.

Усі три виконали вісімнадцять прогонів, кожен окремим процесом, по 300000 ітерацій і сім повторів
на випадок. План пройшов перевірки врівноваженості, записані в кожному файлі: кожен рядок квадрата
є перестановкою шести випадків, кожен випадок стоїть на кожній позиції раз за квадрат, і трапляються
всі 30 упорядкованих пар сусідніх випадків, тож післядію врівноважено. Зерна перемішування рядків
становлять 1787680562, 1787691521 і 1787692683.

Порожній цикл виміряно на початку і в кінці кожного прогону в усіх трьох кампаніях.

Правила з 1 по 5 реалізовано в `runner.py`. Жоден прогін жодної з трьох кампаній не підпав під
ознаки вилучення за правилом 6: прив'язка вдалася в кожному прогоні, а середнє навантаження за
прогін змінювалося щонайбільше на 0,04, 0,02 і 0,11 відповідно.

Кожен прогін прив'язано до ядра 3, і перечитана після прив'язки маска збігається в усіх прогонах
усіх трьох кампаній. Кожній кампанії передувало її пілотне дослідження із шести прогонів з
прив'язкою і шести без неї.

Середовище записано до і після кожної кампанії. Представників зібрано окремим кроком до першого
прогону, і перевірка збірки пройшла в усіх трьох.

#### Зроблено інакше

У кампанії 2 пілотне дослідження дало розмах бази відліку 193,6 % з прив'язкою проти 18,6 % без неї.
За розділом 5 цей результат фіксує рішення про прив'язку, і він свідчив проти неї. Прив'язку все ж
збережено на тій підставі, що обернення пояснюється стороннім навантаженням тієї сесії, а не самою
прив'язкою. Це відступ від протоколу і записаний тут як такий. У кампаніях 1 і 3 пілотне дослідження
свідчило у протилежний бік, 11,1 % проти 256,2 % і 13,1 % проти 71,0 %.

#### Не зроблено

Наведене нижче є відступами від методики вимірювання, а не від протоколу, і розділ 7 їх передбачає.

Частоти не зафіксовано в кампанії 1, яка йшла на регуляторі частоти `ondemand` із ввімкненим важелем
прискорення. У кампаніях 2 і 3 регулятор частоти був `performance`, а важіль прискорення вимкнено,
але важіль прийняв драйвер і не прийняло залізо, тож частота під навантаженням не трималася на
оголошеному максимумі.

Одночасна багатопотоковість була ввімкнена в усіх трьох кампаніях. `PYTHONHASHSEED` не фіксувався.
Контрольної платформи не було, тож кратності відносно бази відліку потребують повторного
вимірювання.

Два суміжні пункти відступами не є. Протокол вимагає прив'язки процесу, а не ізоляції ядра від
планувальника, тож стороннє планування на тому самому ядрі лишається джерелом збурень у межах умов
вимірювання. Частоту запис середовища подає разовими знімками на момент запису, а не по випадках,
тож сталість частоти в межах прогону спирається на її фіксацію, якої в кампанії 1 не було.

#### Спостереження

Прогони пронумеровано від нуля за полем `seq`, і це не та нумерація, яку скрипт друкує на екрані.

Медіана тридцяти шести вимірів порожнього циклу становить 30,70 нс у кампанії 1, 31,64 нс у
кампанії 2 і 30,66 нс у кампанії 3. Окремі виміри лежать від 28,51 до 50,77 нс, від 29,04 до 52,74
нс і від 28,40 до 51,06 нс відповідно. Дрейф усередині прогону має медіану близько нуля в усіх
трьох, але сягає +21,29, −21,48 і +21,63 нс.

Частина прогонів несе збій виміру бази відліку або порожнього циклу. Збоєм виміру тут зветься
відхилення одного з двох вимірів порожнього циклу прогону або його бази відліку від медіани своєї
кампанії більш ніж на 40 %. Цей поріг обрано після даних, правилом протоколу він не є і слугує лише
для того, щоб назвати прогони, про які йдеться нижче.

| Кампанія | Прогони | Що відхиляється |
|---|---|---|
| 1 | 1, 5, 15 | прогін 1, кінцевий порожній цикл 50,32 нс і база 10,47 нс; прогін 5, кінцевий порожній цикл 50,77 нс і база 10,35 нс; прогін 15, база 40,78 нс |
| 2 | 16 | початковий порожній цикл 52,74 нс і база 10,86 нс |
| 3 | 7, 11, 17 | прогін 7, кінцевий порожній цикл 51,06 нс; прогін 11, початковий порожній цикл 46,62 нс; прогін 17, база 44,16 нс |

Медіани бази, відносно яких ці відхилення міряються, становлять 21,62, 22,14 і 21,33 нс. Жоден з цих
прогонів не підпадає під жодну з ознак правила 6, тож усі лишені в основному аналізі своєї кампанії.
Причину не встановлено.

Два різновиди збою впливають на аналіз по-різному. Збій бази відліку спотворює кожну кратність свого
прогону, бо база є знаменником, але попарних оцінок правила 3 не зачіпає, бо база в них не входить.
Збій виміру порожнього циклу спотворює і те, і те, бо порожній цикл віднімається від кожного випадку
адитивно і в логарифмі відношення не скорочується. У кампанії 3 заміна порожнього циклу прогону 7 на
типове значення рухає оцінку розміщення стану того прогону з +21,4 % на +16,6 %, тоді як та сама
заміна в прогоні 17 рухає її з +23,9 % на +24,2 %.

### Основні результати

Це результати, які три кампанії дали за власним протоколом. Вони заміщені й наведені для повноти
запису.

Кратності відносно бази відліку, пораховані всередині кожного прогону (правило 2), медіани з
розмахом:

| Клас | Кампанія 1 | Кампанія 2 | Кампанія 3 |
|---|---|---|---|
| 3 | 1,884 (від 1,074 до 3,114) | 1,944 (від 1,808 до 2,882) | 1,993 (від 0,982 до 2,553) |
| 4 | 1,917 (від 1,059 до 4,693) | 1,937 (від 1,740 до 2,983) | 1,978 (від 0,964 до 2,664) |
| 5 | 2,275 (від 1,268 до 3,764) | 2,415 (від 2,087 до 3,686) | 2,361 (від 1,234 до 3,211) |
| 6 | 21,033 (від 10,909 до 44,072) | 21,369 (від 18,726 до 44,062) | 21,542 (від 10,214 до 33,742) |
| 7 | 2,278 (від 1,222 до 3,720) | 2,339 (від 2,002 до 3,600) | 2,327 (від 1,178 до 3,199) |

Ефекти осей (правила 3 і 4), медіани попарних різниць усередині прогону з бутстреп-інтервалами на
рівні 95 %:

| Величина | Кампанія 1 | Кампанія 2 | Кампанія 3 |
|---|---|---|---|
| розміщення стану, загальний API, 3 → 5 | +19,8 % [+16,6, +22,6] | +23,4 % [+19,0, +28,5] | +20,0 % [+16,9, +25,0] |
| розміщення стану, обмежений API, 4 → 7 | +17,4 % [+15,9, +22,5] | +20,5 % [+16,2, +21,8] | +20,1 % [+16,0, +21,9] |
| рівень втручання, стан в об'єкті, 4 → 3 | −0,0 % [−1,0, +1,8] | +1,4 % [−1,6, +3,3] | +1,0 % [−1,3, +1,7] |
| рівень втручання, таблиця, 7 → 5 | +1,0 % [−0,6, +2,6] | +3,6 % [+1,7, +4,4] | +1,3 % [+0,2, +2,9] |
| ефект розміщення стану | +18,1 % [+15,9, +24,4] | +22,1 % [+17,3, +23,5] | +20,7 % [+16,8, +22,1] |
| ефект рівня втручання | +0,8 % [−0,6, +1,7] | +2,6 % [+1,2, +2,9] | +1,2 % [−0,5, +2,1] |
| взаємодія | +0,9 % [−3,7, +3,5] | +1,9 % [−0,0, +6,4] | +1,7 % [−0,6, +3,9] |

За правилом 4 ефект розміщення стану наявний в усіх трьох кампаніях і подається одним числом, бо
інтервал взаємодії нуль містить. Ефект рівня втручання не встановлений у кампаніях 1 і 3 і наявний у
кампанії 2. Розділ про застосування пояснює, чому колонка рівня втручання цих кампаній не вимірює
різниці між щаблями.

Позиційний ефект (правило 5), зміна значення на одну позицію:

| Випадок | Кампанія 1 | Кампанія 2 | Кампанія 3 |
|---|---|---|---|
| база відліку | +0,24 % | −2,88 % | −4,45 % |
| клас 3 | +3,16 % | −0,34 % | −1,25 % |
| клас 4 | +3,23 % | +1,18 % | +1,15 % |
| клас 5 | −0,32 % | +1,70 % | +2,88 % |
| клас 6 | −1,04 % | −0,51 % | +0,16 % |
| клас 7 | −0,96 % | −0,05 % | −1,08 % |

### Застосування

**Стійкість напряму ефекту розміщення стану.** Ефект оцінено в дев'яти незалежних наборах даних. У
кожному точкова оцінка додатна, між +15,0 % і +23,8 %, і нуля її інтервал не містить у семи з
дев'яти. Два, де містить, є шестипрогоновими пілотними дослідженнями з відповідно широкими
інтервалами. Спільна вада стосується осі рівня втручання, а не цієї.

| Набір | n | Розміщення стану | Рівень втручання |
|---|---|---|---|
| кампанія 1 | 18 | +18,1 % [+15,9, +24,4] | +0,8 % [−0,6, +1,7] |
| кампанія 2 | 18 | +22,1 % [+17,3, +23,5] | +2,6 % [+1,2, +2,9] |
| кампанія 3 | 18 | +20,7 % [+16,8, +22,1] | +1,2 % [−0,5, +2,1] |
| пілотне дослідження 1 з прив'язкою | 6 | +22,0 % [+16,7, +26,9] | +4,0 % [−0,7, +6,8] |
| пілотне дослідження 1 без прив'язки | 6 | +23,8 % [+18,6, +27,3] | +5,3 % [−4,4, +13,6] |
| пілотне дослідження 2 з прив'язкою | 6 | +15,0 % [−3,2, +22,5] | −0,1 % [−18,9, +2,8] |
| пілотне дослідження 2 без прив'язки | 6 | +20,2 % [+16,5, +35,8] | +1,2 % [−0,6, +13,0] |
| пілотне дослідження 3 з прив'язкою | 6 | +18,4 % [−4,0, +23,1] | +1,5 % [+0,2, +3,6] |
| пілотне дослідження 3 без прив'язки | 6 | +23,4 % [+18,1, +32,2] | +3,5 % [+0,7, +6,9] |

**Контроль на однаковому коді для осі рівня втручання.** Вимірюваний код двох збірок був однаковий,
тож істинна різниця між щаблями в цих даних дорівнює нулю за побудовою. Будь-яка ненульова оцінка в
правій колонці вимірює зсув самої процедури, насамперед різницю розкладки коду між двома окремо
зібраними модулями.

По дев'яти наборах ця оцінка лежить від −0,1 % до +5,3 %. Вона додатна у восьми з дев'яти, а її
інтервал не містить нуля у трьох. З одного набору такої частоти не видно.

Межу отримано після даних, і до протоколу вона не входить. Вона характеризує процедуру в тому
вигляді, який вона мала в цих кампаніях, з увімкненою одночасною багатопотоковістю і без вимоги до
вирівнювання гарячих функцій двох збірок, і не переноситься на процедуру, що цими рисами
відрізняється.

### Додаткові аналізи після даних

Наведене нижче виконано після отримання даних. До протоколу воно не входить і вердиктів правила 4
не змінює.

#### Аналіз чутливості

Без прогонів 7, 11 і 17 кампанія 3 дає ефект розміщення стану +20,1 % (від +16,1 % до +21,4 %) і
ефект рівня втручання +1,0 % (від −0,7 % до +2,1 %). Вилучення трьох прогонів порушує рівність трьох
повторень плану Вільямса, тож це оцінка впливу прогонів зі збоєм виміру, а не основний результат.

#### Розрив ярусів

Клас 6 лежить поза критерієм, зафіксованим наперед. Ділення його медіанної кратності на медіанні
кратності класів на C дає розрив від 9,23 до 11,16 раза в кампанії 1, від 8,85 до 11,03 у кампанії
2 і від 9,12 до 10,89 у кампанії 3.

### Відтворення

Аналіз відтворюється з кореня репозиторію:

```text
python3 runner.py --analyze data/campaigns-1-3/campaign-1/campaign.json
```

Аналіз читає лише сирі дані й не звертається ні до `probe.c`, ні до `measure.py`. Якщо код аналізу в
корені змінився після цих кампаній, медіани все одно відтворяться, бо вони детерміновані, тоді як
кінці бутстреп-інтервалів залежать від зерна того коду.

Повторне вимірювання з кореня не відтворюється, бо представники в корені відрізняються від цих. Для
повторного вимірювання потрібні три файли, позначені контрольними сумами вище.
