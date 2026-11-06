# Campaigns 1 to 3 protocol · Протокол кампаній 1 до 3

[English](#english) · [Українська](#українська)

## English

This document summarizes the measurement protocol that was fixed before the first run of campaign 1
and under which campaigns 1, 2 and 3 were run. The summary was written after the campaigns; the full
text of the protocol is not published. The `protocol_md5` field of the raw data files holds the
checksum of this document. How the campaigns were carried out, why they were superseded and what
they found is described in [`REPORT.md`](REPORT.md).

### 1. Measured cases

Six cases: a baseline, a native `float` operation on the specialized path of CPython 3.12, and
minimal representatives of classes 3, 4, 5, 6 and 7. Classes 1 and 2 require modifying the
interpreter core and are not measured.

The measurement code is not modified by the campaign. The functions `bench` and `loop_overhead`,
the `CASES` list and the class `PyObj` are taken from `measure.py` as they are. The runner checks
that the composition of `CASES` still matches its own class list and stops if it does not. The
signature field of `CASES` is not read, because it carries ordinal levels of an earlier revision.

### 2. Run plan

Eighteen runs, each in a separate process. The order of the cases within a run follows a Williams
design over six positions: every case occupies every position exactly three times and follows every
other case exactly three times. The baseline takes part in the permutation like any class. The
eighteen runs are three replicates of the square, and the order of rows within each replicate is
shuffled by a generator with a recorded seed.

### 3. Empty-loop correction

The empty loop is measured twice per run, at the start and at the end. The mean of the two is
subtracted from the median of every case in the same run. The difference between the final and the
initial measurement is recorded as a direct estimate of drift within the run.

### 4. Analysis rules

1. **The unit of analysis is the run.** For every case in every run, the median of seven
   repetitions is taken, less the empty loop as described in section 3.

2. 2. **Ratios are computed within the run.** The ratio of a case is its value divided by the value
   of the baseline in the same run. The ratio column reports the median of the eighteen ratios and
   their range.

3. **Axis effects are estimated from within-run differences of log ratios.** Classes 3, 4, 5 and 7
   form a 2 × 2 design whose first axis is state placement and whose second axis is level of
   intervention:

   ```text
   state placement effect        = mean( ln(t5/t3), ln(t7/t4) )
   level of intervention effect  = mean( ln(t3/t4), ln(t5/t7) )
   interaction                   = ln(t5/t3) − ln(t7/t4)
   ```

   Class 6 is not part of the 2 × 2 design and is reported by its ratio only.

4. **The criterion for an effect is fixed in advance.** An effect is present if the 95% bootstrap
   interval of its median excludes zero. An effect is reported as a single value only if the
   interval of the interaction includes zero; otherwise it is reported separately for each level of
   the other axis.

5. **Position effect.** The position effect is estimated as the slope of the log value on the
   position of the case within the run and is reported as a property of the environment. By
   construction of the Williams design, the contrasts of rule 3 are free of the average position
   effect.

6. **Outliers are not removed.** A run is excluded as a whole only for a technical reason fixed in
   advance: failed pinning to the core, or a change of the machine load average by more than one
   between the start and the end of the run.

The protocol states no prediction for the axis of the level of intervention. The cost signature
assigns the same taxed terms to both levels, and this was read as an expectation of no difference
rather than as a prediction, since the signature does not express magnitudes.

### 5. Core pinning

Pinning is done from inside the process with `sched_setaffinity` before the measurement modules are
imported. The core is the same for all runs of a session and is given as a parameter. The actual
affinity is read back with `sched_getaffinity` and recorded. A refused call is not treated as a
failure; it is recorded as a fact about the environment.

The main campaign is preceded by a pilot of six pinned and six unpinned runs. The spread of the
baseline is compared. The outcome fixes the pinning decision and is stored with the campaign.

### 6. Environment

All attributes of the measurement methodology are recorded, including those the author does not
control: CPU model, number of cores, current frequencies and limits, governor, SMT state, turbo
state, FMA availability, OS kernel, versions of CPython, the compiler and the C library, CPython
build flags, container indicators, load average, checksums of `measure.py`, `probe.c` and the built
extension modules, and the build flags of the representatives together with the compiler version,
which the build step writes to `probe_build.json` and the runner reads.

The representatives are built in a separate step rather than by the measuring process, so that
compilation does not immediately precede the first run. The build step verifies that the built
modules match the source and the recorded flags, and the measuring stages refuse to start if they
do not.

### 7. Scope

The campaign is not a measurement under the full methodology. The caveat that the ratios to the
baseline need to be measured again stays in the article regardless of the outcome.

---

## Українська

Цей документ стисло подає протокол вимірювання, зафіксований до першого прогону кампанії 1, за
яким виконано кампанії 1, 2 і 3. Підсумок написано після кампаній, повний текст протоколу не
публікується. Поле `protocol_md5` файлів сирих даних містить контрольну суму цього документа. Як
кампанії виконано, чому їх заміщено і що вони показали, описано у [`REPORT.md`](REPORT.md).

### 1. Що вимірюється

Шість випадків: база відліку, тобто нативна операція над `float` на спеціалізованому шляху CPython
3.12, і мінімальні представники класів 3, 4, 5, 6 і 7. Класи 1 і 2 потребують модифікації ядра
інтерпретатора і не вимірюються.

Вимірювальний код кампанією не змінюється. Функції `bench` і `loop_overhead`, список `CASES` і клас
`PyObj` беруться з `measure.py` як є. Раннер перевіряє, що склад `CASES` досі відповідає його
власному переліку класів, і зупиняється, якщо ні. Поле сигнатури в `CASES` не читається, бо воно
містить порядкові рівні попередньої редакції.

### 2. План прогонів

Вісімнадцять прогонів, кожен окремим процесом. Порядок випадків у прогоні йде за планом Вільямса на
шість позицій: кожен випадок стоїть на кожній позиції рівно тричі й слідує за кожним іншим рівно
тричі. База відліку бере участь у перестановці нарівні з класами. Вісімнадцять прогонів є трьома
повтореннями квадрата, а порядок рядків усередині кожного повторення перемішує генератор із
записаним зерном.

### 3. Порожній цикл

Порожній цикл вимірюється двічі за прогін, на початку і в кінці. Середнє двох вимірів віднімається
від медіани кожного випадку того самого прогону. Різниця між кінцевим і початковим виміром
записується як пряма оцінка дрейфу всередині прогону.

### 4. Правила аналізу

1. **Одиницею аналізу є прогін.** Для кожного випадку в кожному прогоні береться медіана семи
   повторів з відніманням порожнього циклу за розділом 3.

2. **Кратність рахується всередині прогону.** Кратність випадку є його значенням, поділеним на
   значення бази відліку того самого прогону. Колонка кратностей подає медіану вісімнадцяти
   кратностей і їхній розмах.

3. 3. **Ефекти осей оцінюються попарними різницями логарифмів відношень усередині прогону.** Класи
   3, 4, 5 і 7 утворюють повний факторний план два на два, де перша вісь є розміщенням стану, а
   друга рівнем втручання:

   ```text
   ефект розміщення стану   = середнє( ln(t5/t3), ln(t7/t4) )
   ефект рівня втручання    = середнє( ln(t3/t4), ln(t5/t7) )
   взаємодія                = ln(t5/t3) − ln(t7/t4)
   ```

   Клас 6 у план два на два не входить і подається лише кратністю.

4. 4. **Критерій наявності ефекту зафіксований наперед.** Ефект наявний, якщо бутстреп-інтервал його
   медіани на рівні 95 % не містить нуля. Ефект подається одним числом лише тоді, коли інтервал
   взаємодії нуль містить, інакше він подається окремо для кожного рівня другої осі.

5. **Позиційний ефект.** Оцінюється коефіцієнтом регресії логарифма значення на позицію випадку в
   прогоні і подається як характеристика середовища. За побудовою плану Вільямса попарні оцінки
   правила 3 від середнього позиційного ефекту вільні.

6. **Викиди не вилучаються.** Прогін вилучається цілком лише за технічною ознакою, зафіксованою
   наперед: за невдалої прив'язки до ядра або за зміни середнього навантаження машини більш ніж на
   одиницю між початком і кінцем прогону.

Прогнозу для осі рівня втручання протокол не містить. Вартісна сигнатура приписує обом щаблям
однакові оподатковані доданки, і це читалося як очікування відсутності різниці, а не як прогноз,
бо сигнатура величин не виражає.

### 5. Прив'язка до ядра

Прив'язка виконується зсередини процесу викликом `sched_setaffinity` до імпорту вимірювальних
модулів. Номер ядра однаковий для всіх прогонів сеансу і задається параметром. Фактична прив'язка
перечитується викликом `sched_getaffinity` і записується. Заборона виклику аварією не вважається,
вона записується як факт середовища.

Основній кампанії передує пілотне дослідження із шести прогонів з прив'язкою і шести без неї.
Порівнюється розмах бази відліку. Результат фіксує рішення про прив'язку і зберігається разом з
кампанією.

### 6. Середовище

Записуються всі атрибути методики вимірювання, включно з тими, якими автор не керує: модель
процесора, кількість ядер, поточні частоти і межі, регулятор частоти, стан одночасної
багатопотоковості, стан прискорення, наявність FMA, ядро операційної системи, версії CPython,
компілятора і бібліотеки C, прапорці збірки CPython, ознаки контейнера, середнє навантаження,
контрольні суми `measure.py`, `probe.c` та зібраних модулів розширення, а також прапорці збірки
самих представників разом з версією компілятора, які етап збірки пише у `probe_build.json`, а раннер
читає.

Представників збирає окремий крок, а не процес вимірювання, щоб компіляція не межувала з першим
прогоном. Етап збірки перевіряє, що зібрані модулі відповідають джерелу і записаним прапорцям, а
вимірювальні етапи відмовляються стартувати, якщо ні.

### 7. Межа кампанії

Кампанія не є вимірюванням за повною методикою. Застереження про те, що кратності відносно бази
відліку потребують повторного вимірювання, лишається в статті незалежно від результату.
