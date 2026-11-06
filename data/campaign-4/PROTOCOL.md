# Campaign 4 protocol · Протокол кампанії 4

[English](#english) · [Українська](#українська)

## English

This document summarizes the measurement protocol that was fixed before the first run of
campaign 4. The summary was written after the campaign; the full text of the protocol is not
published. The `protocol_md5` field of the raw data files holds the checksum of this document. How
the campaign was carried out and what it found is described in [`REPORT.md`](REPORT.md).

### Why campaign 4

The representatives used in campaign 3 did not exercise the mechanism through which the two levels
of intervention can differ in cost. With `Py_LIMITED_API` set to `0x030C0000` or higher, `Py_INCREF`
and `Py_DECREF` become calls into the interpreter, but the hot path of the campaign 3
representatives contained no reference-count operation. Both builds therefore executed the same code
on the hot path, and the estimate for the level of intervention compared two builds rather than two
levels. In addition, the deallocators did not release the reference to the heap type that the type
gains on every instance creation, which departs from the documented `tp_dealloc` contract.

Campaign 4 replaces campaign 3 as the campaign reported in the article. This choice was fixed by
the protocol before the campaign was run.

### 1. Measured cases

Six cases are measured: the baseline, a native `float` operation on the specialized path of CPython
3.12, and minimal representatives of classes 3, 4, 5, 6 and 7. Classes 1 and 2 require modifying the
interpreter core and are not measured.

The C representatives differ from those of campaigns 1 to 3 in one change on the measured path.
After freeing an object, the deallocators of both types release the reference to their type. In the
build with the public C API the decrement is inlined; in the limited API build it is a call to
`_Py_DecRef`. Arithmetic, state placement, dispatch route and allocation are unchanged. The other
changes in `probe.c` concern module initialization, constructors and conversion to `float`, and do
not reach the measured path.

The measurement code is unchanged. The functions `bench` and `loop_overhead` and the class `PyObj`
in `measure.py` are those of campaign 3. The `CASES` list carries the class identifier of each
case, and the runner stops if it disagrees with its own class list. The runner only permutes the
order of the cases, starts each run in a separate process and collects the raw data.

### 2. Run plan

Eighteen runs are made, each in a separate process. The order of the cases within a run follows a
Williams design for six positions: across the campaign every case occupies every position exactly
three times and follows every other case exactly three times. The baseline takes part in the
permutation like any class. The eighteen runs are three replicates of the square, and the order of
rows within each replicate is shuffled by a generator with a recorded seed.

### 3. Empty-loop correction

The empty loop is measured twice per run, at the start and at the end. The mean of the two
measurements is subtracted from the median of every case in the same run. The difference between
the final and the initial measurement is recorded as a direct estimate of drift within the run.

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
   interval of the interaction includes zero; otherwise it is reported separately for each level
   of the other axis.

5. **Position effect.** The position effect is estimated as the slope of the log value on the
   position of the case within the run and is reported as a property of the environment. By
   construction of the Williams design, the contrasts of rule 3 are free of the average position
   effect.

6. **Outliers are not removed.** A run is excluded as a whole only for a technical reason fixed in
   advance: failed pinning to the core, or a change of the machine load average by more than one
   between the start and the end of the run.

7. **Predictions are fixed in advance.** Axis effects are taken from rule 3 and their presence
   from rule 4.

   - *Prediction 1, state placement.* Classes with an external table, 5 and 7, are more expensive
     than classes with in-object state, 3 and 4, so the state placement effect is positive.
   - - *Prediction 2, level of intervention.* Limited API classes, 4 and 7, are more expensive than
     classes using the public C API, 3 and 5, so the effect of the level of intervention is
     negative. For every freed object the deallocator releases the reference to the type, which with
     the limited API of version 3.12 is a call into the interpreter and with the public C API an
     inlined decrement. This operation belongs to the life cycle of the result object and works
     against the limited API. The model does not predict magnitudes. Prediction 2 replaces the
     earlier prediction that classes 3 and 4, and 5 and 7, do not differ; that prediction rested on
     the model assigning the same taxed terms to both levels, whereas the cost signature does not
     express magnitudes.

   A prediction is confirmed when the effect is present under rule 4 and has the predicted sign,
   and refuted when the effect is present with the opposite sign. When the interval includes zero,
   the effect is not established and the prediction is neither confirmed nor refuted.

8. 8. **Earlier campaigns.** Reported numbers come from campaign 4 only. For state placement, the
   estimates of campaigns 1, 2 and 3, of the sensitivity analysis of campaign 3 and of the branches
   of its pilot serve as a check on the robustness of the direction of the effect. For the level of
   intervention they are neither compared nor pooled with campaign 4. The campaign 3 estimate on
   this axis, +1.2% with an interval from −0.5% to +2.1%, was obtained on two builds with an
   identical hot path. It is shown next to the campaign 4 result as an estimate of the bias of the
   procedure itself, an A/A control, and does not affect the verdicts under rules 4 and 7.

### 5. Core pinning

Pinning is done from inside the process with `sched_setaffinity` before the measurement modules
are imported. The core is the same for all runs of a session, is chosen among the cores that stay
online with SMT disabled, and is not core 0. The actual affinity is read back with
`sched_getaffinity` and recorded. A refused call is not treated as a failure; it is recorded as a
fact about the environment.

The main campaign is preceded by a pilot of six pinned and six unpinned runs. The spread of the
baseline is compared. The outcome fixes the pinning decision and is stored with the campaign.

### 6. Environment

All attributes of the measurement methodology are recorded, including those the author does not
control: CPU model, number of cores and online cores, current frequencies and limits, governor,
SMT state, turbo state, FMA availability, OS kernel, versions of CPython, the compiler and the C
library, CPython build flags, container indicators, load average, checksums of `measure.py`,
`probe.c` and the built extension modules, and the build flags of the representatives together
with the compiler version, which the build step writes to `probe_build.json` and the runner reads.

Before the campaign the machine is prepared by `prepare_machine.sh`, which checks every step and
stops at the first failure. The machine runs on mains power. The graphical session is stopped, the
browser and the package manager are not running, and background scheduling and update services are
stopped. SMT is disabled. The driver and processor controls that disable frequency boost are set,
and whether they take effect is checked under load. The governor is `performance`, with the lower
and upper frequency limits equal to the fixed frequency. Interrupts that allow it are routed to
core 0, and the NMI watchdog is disabled. Address space layout randomization is left enabled,
since it varies code placement between runs.

The fixed frequency is determined under load. The base frequency of the processor is tried first.
If the measurement core exceeds it under load, meaning the boost controls do not take effect, the
next lower available frequency is fixed, because AMD processors enter boost states only when the
highest regular performance state is requested. Once the frequency is chosen, the script checks
under load that the measurement core holds it, neither exceeding it nor dropping below it. Both
measurements are recorded.

The script writes the machine state to `machine_state.txt` next to the raw data, and the checksums
of this file and of the script itself are stored with the results. If a step fails, the script
stops and records the failed step in `machine_state.txt`; the campaign is then not cancelled, and
the unmet item is reported among the limits of the measurement conditions.

`PYTHONHASHSEED` is a controlled variable of the methodology. The campaign runs with
`PYTHONHASHSEED=0`, and the actual value is recorded with the rest of the environment.

Both builds of the representatives use 64-byte function alignment, so the hot code of the two
modules has the same placement relative to cache lines. The addresses of the hot functions are
recorded in `probe_build.json`. The build step checks that the representatives add correctly,
release the reference to their type and have aligned hot functions; if the check fails, the
campaign does not start. The representatives are built in a separate step rather than by the
measuring process, so that compilation does not immediately precede the first run.

### 7. Scope

The campaign is not a measurement under the full methodology, because it is performed on a single
platform without a control platform. The caveat that the ratios to the baseline need to be measured
again stays in the article regardless of the outcome.

## Українська

Цей документ стисло подає протокол вимірювання, зафіксований до першого прогону кампанії 4.
Підсумок написано після кампанії, повний текст протоколу не публікується. Поле `protocol_md5`
файлів сирих даних містить контрольну суму цього документа. Як кампанію виконано і що вона
показала, описано у [`REPORT.md`](REPORT.md).

### Навіщо кампанія 4

Представники третьої кампанії не проходили через механізм, яким два рівні втручання можуть різнитися
у вартості. За `Py_LIMITED_API` від `0x030C0000` макроси `Py_INCREF` і `Py_DECREF` стають викликами
функцій інтерпретатора, а вимірюваний код представників третьої кампанії не містив жодної операції з
лічильником посилань. Тому обидві збірки виконували той самий вимірюваний код, і оцінка за віссю
рівня втручання порівнювала дві збірки, а не два рівні. Крім того, деалокатори не віддавали
посилання на свій тип, яке тип у купі отримує при кожному створенні екземпляра, тобто відступали від
документованого контракту `tp_dealloc`.

Кампанія 4 заміщує третю як кампанію статті. Цей вибір зафіксовано протоколом до запуску кампанії.

### 1. Що вимірюється

Вимірюються шість випадків: база відліку, тобто нативна операція над `float` на спеціалізованому
шляху CPython 3.12, і мінімальні представники класів 3, 4, 5, 6 і 7. Класи 1 і 2 потребують
модифікації ядра інтерпретатора і не вимірюються.

Представники на C відрізняються від представників кампаній 1, 2 і 3 однією зміною на вимірюваному
шляху. Після знищення об'єкта деалокатори обох типів віддають посилання на тип. У збірці із
загальним публічним C API декремент виконується на місці, у збірці з обмеженим API він є викликом
`_Py_DecRef`. Арифметика, розміщення стану, маршрут диспетчеризації та алокація не змінені. Решта
змін у `probe.c` стосується ініціалізації модуля, конструкторів і перетворення на `float` і на
вимірюваний шлях не потрапляє.

Вимірювальний код не змінюється. Функції `bench` і `loop_overhead` та клас `PyObj` у
`measure.py` збігаються з третьою кампанією. Список `CASES` несе ідентифікатор класу кожного
випадку, і раннер зупиняється, якщо той розходиться з його власним переліком класів. Раннер лише
переставляє порядок випадків, запускає кожен прогін окремим процесом і збирає сирі дані.

### 2. План прогонів

Виконується вісімнадцять прогонів, кожен окремим процесом. Порядок випадків у прогоні задає план
Вільямса на шість позицій: за кампанію кожен випадок стоїть на кожній позиції рівно тричі і після
кожного іншого випадку рівно тричі. База відліку входить у перестановку нарівні з класами.
Вісімнадцять прогонів є трьома повтореннями квадрата, а порядок рядків усередині кожного
повторення перемішує генератор із записаним зерном.

### 3. Поправка на порожній цикл

Порожній цикл вимірюється двічі за прогін, на початку і в кінці. Середнє двох вимірів
віднімається від медіани кожного випадку того самого прогону. Різниця між кінцевим і початковим
вимірами записується як пряма оцінка дрейфу всередині прогону.

### 4. Правила аналізу

1. **Одиницею аналізу є прогін.** Для кожного випадку в кожному прогоні береться медіана семи
   повторів з відніманням порожнього циклу за розділом 3.

2. **Кратність рахується всередині прогону.** Кратність випадку дорівнює його значенню,
   поділеному на значення бази відліку того самого прогону. Колонка кратностей подає медіану
   вісімнадцяти кратностей і їхній розмах.

3. 3. 3. **Ефекти осей оцінюються різницями логарифмів відношень усередині прогону.** Класи 3, 4, 5
   і 7 утворюють повний факторний план два на два, де першою віссю є розміщення стану, а другою
   рівень втручання.

   ```text
   ефект розміщення стану   = середнє( ln(t5/t3), ln(t7/t4) )
   ефект рівня втручання    = середнє( ln(t3/t4), ln(t5/t7) )
   взаємодія                = ln(t5/t3) − ln(t7/t4)
   ```

   Клас 6 до плану два на два не входить і подається лише кратністю.

4. 4. **Критерій наявності ефекту зафіксовано наперед.** Ефект наявний, якщо бутстреп-інтервал його
   медіани на рівні 95 % не містить нуля. Ефект подається одним числом лише тоді, коли інтервал
   взаємодії нуль містить, а інакше окремо для кожного рівня другої осі.

5. **Позиційний ефект.** Позиційний ефект оцінюється нахилом логарифма значення за позицією
   випадку в прогоні і подається як характеристика середовища. Оцінки правила 3 від середнього
   позиційного ефекту вільні за побудовою плану Вільямса.

6. **Викиди не вилучаються.** Прогін вилучається цілком лише з технічної причини, зафіксованої
   наперед: через невдалу прив'язку до ядра або через зміну середнього навантаження машини між
   початком і кінцем прогону більш ніж на одиницю.

7. **Прогнози зафіксовано наперед.** Ефекти осей беруться за правилом 3, їхня наявність за
   правилом 4.

   - *Прогноз 1, розміщення стану.* Класи із зовнішньою таблицею, 5 і 7, дорожчі за класи зі станом
     в об'єкті, 3 і 4, тобто ефект розміщення стану додатний.
   - - *Прогноз 2, рівень втручання.* Класи обмеженого API, 4 і 7, дорожчі за класи загального
     публічного C API, 3 і 5, тобто ефект рівня втручання від'ємний. Для кожного знищеного об'єкта
     деалокатор віддає посилання на тип, і за обмеженого API версії 3.12 це виклик функції
     інтерпретатора, а за загального декремент на місці. Ця операція належить до життєвого циклу
     об'єкта-результату і діє проти обмеженого API. Величин модель не прогнозує. Прогноз 2 заміщує
     попередній прогноз, за яким класи 3 і 4, як і 5 і 7, між собою не розрізняються. Той прогноз
     спирався на те, що модель приписує обом рівням ті самі оподатковані доданки, тоді як вартісна
     сигнатура величин не виражає.

   Прогноз підтверджено, коли ефект за правилом 4 наявний і має прогнозований знак, і спростовано,
   коли ефект наявний і має протилежний знак. Коли інтервал містить нуль, ефект невстановлений, і
   прогноз не підтверджено й не спростовано.

8. 8. 8. **Попередні кампанії.** Звітні числа беруться лише з кампанії 4. За віссю розміщення стану
   оцінки кампаній 1, 2 і 3, аналізу чутливості третьої та гілок її пілотного дослідження слугують
   перевіркою стійкості напряму ефекту. За віссю рівня втручання вони з кампанією 4 не порівнюються
   і не зводяться. Оцінка третьої кампанії за цією віссю, +1,2 % з інтервалом від −0,5 % до +2,1 %,
   отримана на двох збірках з однаковим вимірюваним кодом. Вона подається поруч з результатом
   кампанії 4 як оцінка зміщення самої процедури, тобто як контроль на однаковому коді, і на
   вердикти за правилами 4 і 7 не впливає.

### 5. Прив'язка до ядра

Прив'язка виконується зсередини процесу викликом `sched_setaffinity` до імпорту вимірювальних
модулів. Ядро однакове для всіх прогонів сеансу, обирається серед ядер, що лишаються ввімкненими
після вимкнення одночасної багатопотоковості, і не є ядром 0. Фактичну прив'язку перечитує виклик
`sched_getaffinity`, і вона записується. Відмова виклику не вважається аварією, а записується як
факт середовища.

Основній кампанії передує пілотне дослідження із шести прогонів з прив'язкою і шести без неї.
Порівнюється розмах бази відліку. Результат пілотного дослідження фіксує рішення про прив'язку і
зберігається разом з кампанією.

### 6. Середовище

Записуються всі атрибути методики вимірювання, зокрема ті, якими автор не керує: модель процесора,
кількість ядер і перелік увімкнених ядер, поточні частоти і їхні межі, регулятор частоти, стан
одночасної багатопотоковості, стан прискорення частоти, наявність FMA, ядро операційної системи,
версії CPython, компілятора і бібліотеки C, прапорці збірки CPython, ознаки контейнера, середнє
навантаження, контрольні суми `measure.py`, `probe.c` і зібраних модулів розширення, а також
прапорці збірки самих представників разом з версією компілятора, які етап збірки записує в
`probe_build.json`, а раннер читає.

Перед кампанією машину готує скрипт `prepare_machine.sh`, який перевіряє кожен крок і зупиняється на
першому невдалому. Машина живиться від мережі. Графічний сеанс зупинено, браузер і менеджер пакетів
не працюють, фонові служби планування й оновлень зупинено. Одночасну багатопотоковість вимкнено.
Важелі драйвера і процесора, що вимикають прискорення частоти, встановлено, а чи діють вони,
перевіряється під навантаженням. Регулятор частоти `performance`, нижня і верхня межі частоти
дорівнюють фіксованій частоті. Переривання, які це дозволяють, відведено на ядро 0, сторожовий
таймер NMI вимкнено. Рандомізацію адресного простору лишено ввімкненою, бо вона урізноманітнює
розміщення коду між прогонами.

Фіксовану частоту визначає перевірка під навантаженням. Першою перевіряється базова частота
процесора. Якщо вимірювальне ядро під навантаженням її перевищує, тобто важелі прискорення не
діють, фіксованою стає наступна нижча доступна частота, бо процесори AMD переходять у стани
прискорення лише тоді, коли запитано найвищий звичайний стан продуктивності. Після вибору частоти
скрипт перевіряє під навантаженням, що вимірювальне ядро її тримає, не перевищуючи і не
опускаючись нижче. Обидва виміри записуються.

Скрипт записує стан машини у файл `machine_state.txt` поруч із сирими даними, а контрольні суми
цього файлу і самого скрипта зберігаються разом з результатами. Якщо якийсь крок не вдається,
скрипт зупиняється і записує невдалий крок у `machine_state.txt`. Кампанія тоді не скасовується, а
невиконаний пункт подається серед меж умов вимірювання.

`PYTHONHASHSEED` є контрольованою змінною методики. Кампанія запускається з `PYTHONHASHSEED=0`, а
фактичне значення записується разом з рештою середовища.

Обидві збірки представників мають вирівнювання функцій на 64 байти, тож вимірюваний код двох модулів
має однакове розміщення відносно рядків кешу. Адреси гарячих функцій записуються в
`probe_build.json`. Етап збірки перевіряє, що представники правильно додають, віддають посилання на
тип і мають вирівняні гарячі функції, і за невдалої перевірки кампанія не запускається.
Представників збирає окремий крок, а не процес вимірювання, щоб компіляція не межувала з першим
прогоном.

### 7. Межа кампанії

Кампанія не є вимірюванням за повною методикою, бо виконується на одній платформі без контрольної.
Застереження про повторне вимірювання кратностей лишається в статті незалежно від результату.
