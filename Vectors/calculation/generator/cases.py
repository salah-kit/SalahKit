# Executed by gen.py, which defines add(), P(), the places and REF.

R2 = "RFC 0002 §4.2, §4.3"
CORE_DAY = "RFC 0001 §4.3, §4.6 (day)"

# ordinary ------------------------------------------------------------------------------------

F = "ordinary"
add(F, "day.makkah-umm-al-qura", "Makkah, Umm al-Qura, 2026-10-13: a complete day of six events at SalahTimes' instants, ordinary and without iqama; Isha is Maghrib plus 90 minutes.",
    f"{R2} step 5; {REF}", makkah, P("ummAlQura"), {"type": "day", "day": "2026-10-13"})
add(F, "day.cairo-egyptian", "Cairo, Egyptian General Authority of Survey (19.5° and 17.5°), 2026-01-15: a complete winter day.",
    f"{R2}; {REF}", cairo, P("egyptian"), {"type": "day", "day": "2026-01-15"})
add(F, "day.istanbul-diyanet", "Istanbul, Diyanet, 2026-06-21: the method's adjustments (sunrise −7, Dhuhr +5, Asr +4, Maghrib +7 minutes) pass through in the settings and the instants.",
    f"{R2}; RFC 0002 §4.1 (every parameter passes through); {REF}", istanbul, P("diyanet"), {"type": "day", "day": "2026-06-21"})
add(F, "day.london-moonsighting-committee", "London, Moonsighting Committee, 2026-12-21: the seasonal Fajr and Isha rules with their method adjustments.",
    f"{R2}; RFC 0002 §4.1; {REF}", london, P("moonsightingCommittee"), {"type": "day", "day": "2026-12-21"})
add(F, "day.jakarta-kemenag", "Jakarta, Kemenag, 2026-04-01: rounding up, a Maghrib angle of 1° and method adjustments on every kind.",
    f"{R2}; RFC 0002 §4.1; {REF}", jakarta, P("kemenag"), {"type": "day", "day": "2026-04-01"})
add(F, "day.new-york-isna-hanafi", "New York, ISNA with Hanafi Asr (CalculationSettings(method: .isna, madhab: .hanafi)), 2026-09-22.",
    f"{R2}; RFC 0002 §4.1 (init(method:madhab:ramadanIsha:)); {REF}", newyork, P("isna", madhab="hanafi"), {"type": "day", "day": "2026-09-22"})
add(F, "day.singapore-muis", "Singapore, MUIS, 2026-03-20: rounding up and a one-minute Dhuhr adjustment.",
    f"{R2}; {REF}", singapore, P("muis"), {"type": "day", "day": "2026-03-20"})
add(F, "day.buenos-aires-mwl", "Buenos Aires, Muslim World League, 2026-06-21: a southern-hemisphere winter day.",
    f"{R2}; {REF}", buenosaires, MWL, {"type": "day", "day": "2026-06-21"})
add(F, "day.makkah-defaulted-parameters", "Makkah, settings whose parameters give only fajr and isha (18° and 17°): every other key decodes as SalahTimes' default (sunset Maghrib, Shafi'i, recommended rule, nearest minute), the same day as the Muslim World League preset.",
    f"RFC 0002 §4.1 (missing parameter keys decode as their defaults); {R2}; {REF}", makkah, {"fajr": {"angle": 18}, "isha": {"angle": 17}}, {"type": "day", "day": "2026-10-13"})
add(F, "day.makkah-user-adjustments-rounding-up", "Makkah, Umm al-Qura with user adjustments (Fajr −2, Isha +5 minutes) and rounding up, 2026-10-12: the adjusted, rounded instants come through unchanged.",
    f"RFC 0002 §4.1, §4.3 step 4 (kept at SalahTimes' instant, unchanged); {REF}", makkah, P("ummAlQura", adjustments={"fajr": -2, "isha": 5}, rounding="up"), {"type": "day", "day": "2026-10-12"})
add(F, "day-containing.makkah-noon", "dayContaining at 12:00 on 2026-10-13 in Makkah is the calculated day 2026-10-13.",
    f"RFC 0001 §4.6 (day(containing:)); {R2}; {REF}", makkah, P("ummAlQura"), {"type": "dayContaining", "date": local(makkah, 2026, 10, 13, 12, 0)})
add(F, "events.cairo-whole-day", "Events of Cairo's 2026-01-15, midnight to midnight: the six events and complete coverage. The neighboring days are complete, so no window appears.",
    f"RFC 0001 §4.6 (events, coverage); {R2}; {REF}", cairo, P("egyptian"), {"type": "events", "from": local(cairo, 2026, 1, 15, 0, 0), "through": local(cairo, 2026, 1, 16, 0, 0)})
add(F, "state.makkah-before-dhuhr", "State at 11:55 on 2026-10-13 in Makkah: previous is sunrise, latestPrayer Fajr, next and nextPrayer Dhuhr (12:07), approaching since 11:52; it changes at Dhuhr.",
    f"RFC 0001 §4.7; {R2}; {REF}", makkah, P("ummAlQura"), {"type": "state", "at": local(makkah, 2026, 10, 13, 11, 55)},
    statuses=["2026-10-13/fajr", "2026-10-13/sunrise", "2026-10-13/dhuhr", "2026-10-13/asr", "2026-10-14/fajr"])

# owning-days ---------------------------------------------------------------------------------

F = "owning-days"
LEADP = "RFC 0001 §4.3 rule 4, §4.6 (context reads civil(b + lead)), §10 #1; RFC 0002 §4.4"
add(F, "day.kashgar-isha-after-midnight", "Kashgar on China Standard Time, Muslim World League, 2026-06-21: Isha is at 00:19 on 06-22 and belongs to 06-21. The day is complete.",
    f"{R2}; RFC 0002 §4.4; RFC 0001 §4.3 rule 4; {REF}", kashgar, MWL, {"type": "day", "day": "2026-06-21"})
add(F, "day-containing.kashgar-0010", "dayContaining at 00:10 on 2026-06-22 in Kashgar is 06-22's day (Fajr 05:28 onward), not 06-21's overnight Isha.",
    f"RFC 0001 §4.6 (day(containing:) is the civil date); {REF}", kashgar, MWL, {"type": "dayContaining", "date": local(kashgar, 2026, 6, 22, 0, 10)})
add(F, "events.kashgar-across-midnight", "Events from 22:00 on 06-21 to 01:00 on 06-22 in Kashgar: 06-21's Maghrib (22:27) and Isha (00:19), both owned by 06-21; coverage is complete.",
    f"RFC 0001 §4.6 (events); {R2}; {REF}", kashgar, MWL, {"type": "events", "from": local(kashgar, 2026, 6, 21, 22, 0), "through": local(kashgar, 2026, 6, 22, 1, 0)})
add(F, "state.kashgar-0010", "State at 00:10 on 06-22 in Kashgar: previous is 06-21's Maghrib, next 06-21's Isha at 00:19, approaching since 00:04; 06-22's Fajr is upcoming.",
    f"RFC 0001 §4.7; {R2}; {REF}", kashgar, MWL, {"type": "state", "at": local(kashgar, 2026, 6, 22, 0, 10)},
    statuses=["2026-06-21/maghrib", "2026-06-21/isha", "2026-06-22/fajr"])
add(F, "day.kazan-fajr-before-midnight", "Kazan on Moscow time, Muslim World League with the middle-of-the-night rule, 2026-06-20: Fajr falls at 23:45 on 06-19, within the 12-hour lead, and belongs to 06-20. Isha at 23:45 equals 06-21's Fajr, which stays (equal instants are allowed across days). The day is complete.",
    f"{R2} step 3 (equal instants stay); {LEADP}; {REF}", kazan, KAZAN, {"type": "day", "day": "2026-06-20"})
add(F, "day.kazan-2026-06-19", "Kazan, 2026-06-19: Fajr at 23:45 on 06-18 and Isha at 23:45, equal to 06-20's Fajr. Complete.",
    f"{R2} step 3; {LEADP}; {REF}", kazan, KAZAN, {"type": "day", "day": "2026-06-19"})
add(F, "events.kazan-before-midnight", "Events from 23:00 to 23:59 on 06-19 in Kazan: 06-19's Isha and 06-20's Fajr, both at 23:45, in events order (owning day breaks the tie). The query ends before midnight, but the context reads up to civil(b + 12 h) = 06-20.",
    f"RFC 0001 §4.6 (context with a lead, events order); {LEADP}; {REF}", kazan, KAZAN, {"type": "events", "from": local(kazan, 2026, 6, 19, 23, 0), "through": local(kazan, 2026, 6, 19, 23, 59)})
add(F, "day-containing.kazan-2350", "dayContaining at 23:50 on 06-19 in Kazan is 06-19's day, although 06-20's Fajr has already begun.",
    f"RFC 0001 §4.6 (day(containing:)); {REF}", kazan, KAZAN, {"type": "dayContaining", "date": local(kazan, 2026, 6, 19, 23, 50)})
add(F, "state.kazan-2320", "State at 23:20 on 06-19 in Kazan: next and nextPrayer are 06-19's Isha (23:45), which comes first of the two events at 23:45 in events order; not yet approaching (23:30).",
    f"RFC 0001 §4.7 (ties follow the events order); {LEADP}; {REF}", kazan, KAZAN, {"type": "state", "at": local(kazan, 2026, 6, 19, 23, 20)},
    statuses=["2026-06-19/maghrib", "2026-06-19/isha", "2026-06-20/fajr"])
add(F, "state.kazan-2345", "State at 23:45 on 06-19 in Kazan, the instant of 06-19's Isha and 06-20's Fajr: previous and latestPrayer are 06-20's Fajr, the later of the tie in events order, and it has just started; next is 06-20's sunrise (02:58).",
    f"RFC 0001 §4.7 (previous: the latest event, ties by events order; justStarted); {LEADP}; {REF}", kazan, KAZAN, {"type": "state", "at": local(kazan, 2026, 6, 19, 23, 45)},
    statuses=["2026-06-19/isha", "2026-06-20/fajr", "2026-06-20/sunrise", "2026-06-20/dhuhr"])
add(F, "state.kazan-0030", "State at 00:30 on 06-20 in Kazan: today's Fajr began 45 minutes before midnight, so previous and latestPrayer are 06-20's Fajr; its just-started window ended at 00:00. Next is sunrise.",
    f"RFC 0001 §4.7; {LEADP}; {REF}", kazan, KAZAN, {"type": "state", "at": local(kazan, 2026, 6, 20, 0, 30)},
    statuses=["2026-06-20/fajr", "2026-06-20/sunrise", "2026-06-20/dhuhr"])
add(F, "state.kazan-bound-before-midnight", "State at 23:50 on 06-19 in Kazan, through 23:55: the bound is before midnight, yet 06-20's Fajr (23:45) is previous because the context reads civil(b + 12 h). 06-20's Fajr has just started (until 00:00). Nothing falls by the bound, so next is null, and the state doesn't change within it.",
    f"RFC 0001 §4.6 (context), §4.7 (an event after b is never next); {LEADP}; {REF}", kazan, KAZAN,
    {"type": "state", "at": local(kazan, 2026, 6, 19, 23, 50), "through": local(kazan, 2026, 6, 19, 23, 55)})
ADJ_EARLY = P("ummAlQura", adjustments={"fajr": -300})
add(F, "day.makkah-fajr-adjusted-before-midnight", "Makkah, Umm al-Qura with a user adjustment of −300 minutes on Fajr, 2026-10-13: Fajr moves to 23:59 on 10-12, inside [start(D) − 12 h, start(D + 2)), and stays with 10-13. 10-12's Isha (19:29) is earlier, so nothing gives way.",
    f"{R2} step 4; RFC 0002 §4.4 (12 hours covers large user adjustments); {REF}", makkah, ADJ_EARLY, {"type": "day", "day": "2026-10-13"})
add(F, "events.makkah-fajr-adjusted-before-midnight", "Events from 23:00 on 10-12 to 00:30 on 10-13 in Makkah with Fajr adjusted by −300 minutes: 10-13's Fajr at 23:59 on 10-12.",
    f"RFC 0001 §4.6 (context with a lead); {R2}; {REF}", makkah, ADJ_EARLY, {"type": "events", "from": local(makkah, 2026, 10, 12, 23, 0), "through": local(makkah, 2026, 10, 13, 0, 30)})

# polar -----------------------------------------------------------------------------------------

F = "polar"
POL = f"{R2} step 4 (doesNotOccur); RFC 0002 §4.5; {REF}"
add(F, "day.tromso-polar-day", "Tromsø, Muslim World League, 2026-06-21 (polar day): only Dhuhr and Asr occur. Fajr, sunrise, Maghrib and Isha are missing with calculationUnavailable.",
    POL, tromso, MWL, {"type": "day", "day": "2026-06-21"})
add(F, "day.tromso-polar-night", "Tromsø, Muslim World League, 2026-12-21 (polar night): Fajr, Dhuhr and Isha occur, from the recommended rule's bounds; sunrise, Asr and Maghrib are missing.",
    POL, tromso, MWL, {"type": "day", "day": "2026-12-21"})
add(F, "events.tromso-polar-day", "Events of 2026-06-21 at Tromsø, midnight to midnight: Dhuhr and Asr. Each missing kind's window runs between the known events around it, across the neighboring days: the night from 06-20's Asr to 06-21's Dhuhr, and from 06-21's Asr to 06-22's Dhuhr, clipped to the request.",
    f"RFC 0001 §4.6 (missing-event windows, clipping); {POL}", tromso, MWL, {"type": "events", "from": local(tromso, 2026, 6, 21, 0, 0), "through": local(tromso, 2026, 6, 22, 0, 0)})
add(F, "state.tromso-polar-day-afternoon", "State at 15:00 on 06-21 at Tromsø: previous is Dhuhr and next is Asr (17:58). No window lies between them, so the state is available.",
    f"RFC 0001 §4.7; {POL}", tromso, MWL, {"type": "state", "at": local(tromso, 2026, 6, 21, 15, 0)},
    statuses=["2026-06-21/dhuhr", "2026-06-21/asr", "2026-06-22/dhuhr"])
add(F, "state.tromso-polar-day-evening", "State at 20:00 on 06-21 at Tromsø: Asr has passed, and the windows of 06-21's Maghrib and Isha and 06-22's Fajr and sunrise run until 06-22's Dhuhr. No event is usable, so the state is unavailable until 06-22's Dhuhr.",
    f"RFC 0001 §4.7 (availability, changesAt); {POL}", tromso, MWL, {"type": "state", "at": local(tromso, 2026, 6, 21, 20, 0)})
add(F, "state.tromso-polar-night-morning", "State at 10:00 on 12-21 at Tromsø: sunrise's window runs from Fajr to Dhuhr. It holds only sunrise, so latestPrayer is Fajr and nextPrayer Dhuhr, while previous and next are null.",
    f"RFC 0001 §4.7 (W_p excludes a window holding only sunrise; status of nextPrayer when next is null); {POL}", tromso, MWL, {"type": "state", "at": local(tromso, 2026, 12, 21, 10, 0)},
    statuses=["2026-12-21/fajr", "2026-12-21/dhuhr", "2026-12-21/isha"])
add(F, "state.tromso-polar-night-afternoon", "State at 14:00 on 12-21 at Tromsø: Asr and Maghrib are missing between Dhuhr and Isha, so no field is known until Isha (16:44).",
    f"RFC 0001 §4.7; {POL}", tromso, MWL, {"type": "state", "at": local(tromso, 2026, 12, 21, 14, 0)})
DIS = P("muslimWorldLeague", highLatitudeRule="disabled")
add(F, "day.oslo-rule-disabled", "Oslo, Muslim World League with the high-latitude rule disabled, 2026-06-21: the Sun never reaches 18° or 17° below the horizon, so Fajr and Isha are missing with calculationUnavailable.",
    POL, oslo, DIS, {"type": "day", "day": "2026-06-21"})
add(F, "state.oslo-rule-disabled-night", "State at 01:00 on 06-22 in Oslo with the rule disabled: the windows of 06-21's Isha and 06-22's Fajr run from 06-21's Maghrib (22:44) to 06-22's sunrise (03:54). The state is unavailable until sunrise.",
    f"RFC 0001 §4.6, §4.7; {POL}", oslo, DIS, {"type": "state", "at": local(oslo, 2026, 6, 22, 1, 0)})

# ordering ------------------------------------------------------------------------------------

F = "ordering"
ORD = f"{R2} step 4 (strictly after the last kept kind); RFC 0001 §4.3 rule 5; RFC 0002 §9 #1, #2; {REF}"
NEXT = f"{R2} step 3 (the earlier day gives way); RFC 0001 §4.3 rule 6, §9 #3; {REF}"
TEH = P("tehran")
add(F, "day.oslo-tehran-tie", "Oslo, Tehran's method, 2026-06-21: Maghrib (4.5°) and Isha (14°) are both bounded by the same seventh of the night and fall at the same instant, so Isha, the later kind of the tie, is missing.",
    ORD, oslo, TEH, {"type": "day", "day": "2026-06-21"})
add(F, "day.oslo-tehran-tie-2026-07-14", "Oslo, Tehran's method, 2026-07-14, the last day of the 2026 tie season: Isha is missing.",
    ORD, oslo, TEH, {"type": "day", "day": "2026-07-14"})
add(F, "day.oslo-tehran-after-ties", "Oslo, Tehran's method, 2026-07-15: Isha is a minute after Maghrib again, and the day is complete.",
    ORD, oslo, TEH, {"type": "day", "day": "2026-07-15"})
add(F, "state.oslo-tehran-tie-night", "State at 23:30 on 06-21 in Oslo, Tehran's method: Maghrib was at 23:28 and Isha is missing, with a window from Maghrib to 06-22's Fajr. Nothing is known until Fajr.",
    f"RFC 0001 §4.7; {ORD}", oslo, TEH, {"type": "state", "at": local(oslo, 2026, 6, 21, 23, 30)})
DIY = P("diyanet")
add(F, "day.arctic-diyanet-inversions", "66° N, 25° E (Europe/Helsinki), Diyanet, 2026-07-01: Fajr (01:34) is after sunrise moved by its −7 minutes (01:32), and Isha (01:07) is before Maghrib moved by its +7 minutes (01:08). Of each inverted pair the later kind, sunrise and Isha, is missing.",
    ORD, arctic, DIY, {"type": "day", "day": "2026-07-01"})
add(F, "day.arctic-diyanet-tie", "66° N, 25° E, Diyanet, 2026-06-10: Maghrib and Isha both at 01:04 on 06-11; Isha is missing.",
    ORD, arctic, DIY, {"type": "day", "day": "2026-06-10"})
UQ = P("ummAlQura")
add(F, "day.rovaniemi-isha-after-next-fajr", "66.5° N, 25.7° E (Europe/Helsinki), Umm al-Qura, 2026-06-01: Isha, 90 minutes after a Maghrib at 00:24 on 06-02, would be after 06-02's Fajr (01:51), so it is missing; Maghrib stays.",
    NEXT, rovaniemi, UQ, {"type": "day", "day": "2026-06-01"})
add(F, "day.rovaniemi-next-day-keeps-fajr", "66.5° N, 25.7° E, Umm al-Qura, 2026-06-02: the following day keeps its Fajr (01:51). Its own Isha is after 06-03's Fajr, so it is missing too.",
    NEXT, rovaniemi, UQ, {"type": "day", "day": "2026-06-02"})
add(F, "day.rovaniemi-last-complete", "66.5° N, 25.7° E, Umm al-Qura, 2026-05-31: Isha (01:48 on 06-01) is before 06-01's Fajr (01:55), so the day is complete.",
    NEXT, rovaniemi, UQ, {"type": "day", "day": "2026-05-31"})
add(F, "events.rovaniemi-missing-isha", "Events from 12:00 on 06-01 to 12:00 on 06-02 at 66.5° N: 06-01's Dhuhr, Asr and Maghrib, and 06-02's Fajr and sunrise. 06-01's Isha has a window from its Maghrib to 06-02's Fajr.",
    f"RFC 0001 §4.6; {NEXT}", rovaniemi, UQ, {"type": "events", "from": local(rovaniemi, 2026, 6, 1, 12, 0), "through": local(rovaniemi, 2026, 6, 2, 12, 0)})
add(F, "state.rovaniemi-before-maghrib", "State at 23:00 on 06-01 at 66.5° N: previous is Asr and next Maghrib (00:24). The Isha window starts at Maghrib, so it doesn't hide Maghrib.",
    f"RFC 0001 §4.7; {NEXT}", rovaniemi, UQ, {"type": "state", "at": local(rovaniemi, 2026, 6, 1, 23, 0)},
    statuses=["2026-06-01/asr", "2026-06-01/maghrib", "2026-06-02/fajr"])
add(F, "state.rovaniemi-after-maghrib", "State at 00:30 on 06-02 at 66.5° N: Maghrib has passed and 06-01's Isha window runs until 06-02's Fajr (01:51), so the state is unavailable until then.",
    f"RFC 0001 §4.7; {NEXT}", rovaniemi, UQ, {"type": "state", "at": local(rovaniemi, 2026, 6, 2, 0, 30)})
add(F, "day.makkah-isha-adjusted-into-next-day", "Makkah, Umm al-Qura with a user adjustment of +1440 minutes on Isha, 2026-10-13: Isha falls at 19:28 on 10-14, inside the owning span but after 10-14's Fajr, so it is missing.",
    NEXT, makkah, P("ummAlQura", adjustments={"isha": 1440}), {"type": "day", "day": "2026-10-13"})
LATER = f"{R2} step 3 (every later day whose times can come first, past a day without times); RFC 0001 §4.3 rule 6; {REF}"
add(F, "day.apia-fajr-after-skipped-date", "Apia, Muslim World League with Fajr adjusted by −600 minutes, 2011-12-29: 12-30 is skipped and has no times, so 12-31 is the next day that does. Its Fajr falls at 19:42 on 12-29, before 12-29's Maghrib (19:57) and Isha (21:12), so they are missing: no event of a day follows an event of a later day.",
    LATER, apia, P("muslimWorldLeague", adjustments={"fajr": -600}), {"type": "day", "day": "2011-12-29"})
polar = Location(-81.73368, -180, "Etc/GMT+4")
FUZZ = P("muslimWorldLeague", fajr={"angle": 18}, maghrib={"angle": 4}, isha={"angle": 17.5}, madhab="hanafi",
         highLatitudeRule="middleOfTheNight", nightSpan="sunsetToSunrise", rounding="up",
         adjustments={"fajr": -826, "sunrise": -10, "dhuhr": 4, "asr": -24, "maghrib": 25, "isha": 720})
add(F, "day.polar-isha-after-fajr-two-days-later", "81.7° S, 180° on UTC−4 (Etc/GMT+4), Hanafi, the middle-of-the-night rule, rounding up and user adjustments from Fajr −826 to Isha +720 minutes, 2056-04-12, a case found by fuzzing: every time of 04-13 is after 04-14's Fajr (18:39 on 04-13), so 04-13 is unavailable. 04-12's Isha (19:15 on 04-13) is after that Fajr too, so it is missing, although 04-13 has nothing left to compare it with.",
    LATER, polar, FUZZ, {"type": "day", "day": "2056-04-12"})
add(F, "day.polar-day-between-is-unavailable", "The same place and settings, 2056-04-13: every time is after 04-14's Fajr (18:39 on 04-13), so nothing is left and the day is unavailable with calculationUnavailable.",
    LATER, polar, FUZZ, {"type": "day", "day": "2056-04-13"})

# failures ------------------------------------------------------------------------------------

F = "failures"
FAIL = "RFC 0002 §4.2 step 1-2, §4.3 steps 1-3, §4.5"
add(F, "day.latitude-95", "Latitude 95: SalahTimes rejects the coordinates, so every day is unavailable with invalidData.",
    f"{FAIL} (invalid coordinates); SalahTimes' algorithm section 2", Location(95, 39.8262, "Asia/Riyadh"), UQ, {"type": "day", "day": "2026-10-13"})
add(F, "events.latitude-95", "Events from 12:00 to 13:00 with latitude 95: no events, and one invalidData gap for each context day whose window reaches the request (06-20 to 06-22).",
    f"{FAIL}; RFC 0001 §4.6 (windows of unavailable days)", Location(95, 39.8262, "Asia/Riyadh"), UQ,
    {"type": "events", "from": local(makkah, 2026, 6, 21, 12, 0), "through": local(makkah, 2026, 6, 21, 13, 0)})
add(F, "day.negative-fajr-angle", "A Fajr angle of −18°: SalahTimes rejects the parameters, so the day is unavailable with invalidData.",
    f"{FAIL} (invalid parameters); SalahTimes' algorithm section 2", makkah, P("muslimWorldLeague", fajr={"angle": -18}), {"type": "day", "day": "2026-10-13"})
add(F, "day.isha-interval-too-long", "An Isha interval of 2000 minutes (SalahTimes accepts 0 to 1440): invalidData.",
    f"{FAIL} (invalid parameters); SalahTimes' algorithm section 2", makkah, P("ummAlQura", isha={"minutesAfterMaghrib": 2000}), {"type": "day", "day": "2026-10-13"})
add(F, "day.year-999", "The year 999 is before SalahTimes' supported range (1000 to 3000): unavailable with calculationUnavailable.",
    f"{FAIL} (unsupported year)", makkah, UQ, {"type": "day", "day": "0999-12-31"})
add(F, "day.year-3001", "The year 3001 is after SalahTimes' supported range: unavailable with calculationUnavailable.",
    f"{FAIL} (unsupported year)", makkah, UQ, {"type": "day", "day": "3001-01-01"})
add(F, "day.year-1000-first-supported-day", "1000-01-01 in Makkah, the first supported day, in the proleptic Gregorian calendar: complete. The instants are written in UTC because Asia/Riyadh then kept local mean time (+03:06:52).",
    f"{R2}; RFC 0001 §4.1 (proleptic Gregorian); {REF}", makkah, UQ, {"type": "day", "day": "1000-01-01"})
add(F, "day.year-3000-last-supported-day", "3000-12-31 in Jakarta, Kemenag, the last supported day: the next day can't be calculated, so nothing is removed for it, and the day is complete.",
    f"{R2} step 3 (only a next day that succeeds removes times); {REF}", jakarta, P("kemenag"), {"type": "day", "day": "3000-12-31"})
add(F, "day.february-30", "2026-02-30 isn't a real date: unavailable with invalidData.",
    f"{FAIL} (step 1); RFC 0001 §4.1", makkah, UQ, {"type": "day", "day": "2026-02-30"})
add(F, "day.apia-skipped-date", "Pacific/Apia skipped 2011-12-30 when it moved across the date line: the date has no time on the clock, so it is unavailable with calculationUnavailable rather than repeating 12-31's solar day.",
    f"{FAIL} (step 1 of §4.3); RFC 0001 §4.1", apia, MWL, {"type": "day", "day": "2011-12-30"})
add(F, "day.apia-before-skipped-date", "Apia, 2011-12-29, the last day at UTC−10: the next date can't be calculated, so nothing is removed for it, and the day is complete.",
    f"{R2} step 3; {REF}", apia, MWL, {"type": "day", "day": "2011-12-29"})
add(F, "day.apia-after-skipped-date", "Apia, 2011-12-31, the first day at UTC+14: complete.",
    f"{R2}; {REF}", apia, MWL, {"type": "day", "day": "2011-12-31"})
add(F, "events.apia-across-skipped-date", "Events from 18:00 on 12-29 (UTC−10) to 08:00 on 12-31 (UTC+14) in Apia: 12-29's Maghrib and Isha, and 12-31's Fajr and sunrise. The skipped 12-30 has one calculationUnavailable gap from 12-29's Isha to 12-31's Fajr.",
    f"RFC 0001 §4.6 (a skipped date is still a context day); {FAIL}; {REF}", apia, MWL,
    {"type": "events", "from": local(apia, 2011, 12, 29, 18, 0), "through": local(apia, 2011, 12, 31, 8, 0)})
ALL = {k: 1440 for k in KINDS}
add(F, "day.nothing-left", "Method and user adjustments of +1440 minutes each on every kind move every event two days later, beyond start(D + 2): no kind is left, so the day is unavailable with calculationUnavailable.",
    f"{R2} step 4; RFC 0002 §4.5 (no kind left); {REF}", makkah, P("ummAlQura", methodAdjustments=ALL, adjustments=ALL), {"type": "day", "day": "2026-10-13"})
add(F, "day.fajr-before-lead", "Makkah, Umm al-Qura with Fajr adjusted by −1100 minutes, 2026-10-13: Fajr would fall at 10:39 on 10-12, before start(D) − 12 h (12:00 on 10-12), so it is missing; the rest of the day is kept.",
    f"{R2} step 4 (before start(X) − L); RFC 0002 §4.4; {REF}", makkah, P("ummAlQura", adjustments={"fajr": -1100}), {"type": "day", "day": "2026-10-13"})
add(F, "day.fajr-at-lead", "Makkah, Umm al-Qura with Fajr adjusted by −1019 minutes, 2026-10-13: Fajr falls at 12:00 on 10-12, exactly start(D) − 12 h. The bound is inclusive, so it is kept. 10-14's Fajr falls at 12:01 on 10-13, before 10-13's Dhuhr (12:07), so Dhuhr, Asr, Maghrib and Isha give way.",
    f"{R2} steps 3-4 (start(X) − L is inside the span); RFC 0002 §4.4; {REF}", makkah, P("ummAlQura", adjustments={"fajr": -1019}), {"type": "day", "day": "2026-10-13"})
add(F, "day.fajr-a-minute-before-lead", "Makkah, Umm al-Qura with Fajr adjusted by −1020 minutes, 2026-10-13: Fajr would fall at 11:59 on 10-12, a minute before start(D) − 12 h, so it is missing. 10-14's Fajr falls at 12:00 on 10-13, exactly on its own bound, so it is kept, and 10-13's Dhuhr, Asr, Maghrib and Isha, after it, give way: only sunrise is left.",
    f"{R2} steps 3-4 (before start(X) − L); RFC 0002 §4.4; {REF}", makkah, P("ummAlQura", adjustments={"fajr": -1020}), {"type": "day", "day": "2026-10-13"})

# opt-ins ---------------------------------------------------------------------------------------

F = "opt-ins"
RAM = f"RFC 0002 §4.6 (Ramadan Isha); SalahTimes RFC 0001 decision 7; {REF}"
R120 = P("ummAlQura", ramadanIsha={"interval": {"minutes": 120, "hijriDayOffset": 0}})
add(F, "day.makkah-ramadan-off", "Makkah, Umm al-Qura, 2026-03-01 (12 Ramadan 1447) with the Ramadan rule off: Isha is Maghrib plus 90 minutes.",
    RAM, makkah, UQ, {"type": "day", "day": "2026-03-01"})
add(F, "day.makkah-ramadan-on", "The same day with ramadanIsha {interval: 120 minutes} (CalculationSettings(method: .ummAlQura, ramadanIsha: …)): Isha is Maghrib plus 120 minutes; nothing else changes.",
    RAM, makkah, R120, {"type": "day", "day": "2026-03-01"})
add(F, "day.makkah-ramadan-last-day", "2026-03-19, the last day of Ramadan 1447 in the Umm al-Qura calendar, with the rule on: Isha is Maghrib plus 120 minutes.",
    RAM, makkah, R120, {"type": "day", "day": "2026-03-19"})
add(F, "day.makkah-after-ramadan", "2026-03-20, the day after Ramadan, with the rule on: Isha is back to Maghrib plus 90 minutes.",
    RAM, makkah, R120, {"type": "day", "day": "2026-03-20"})
add(F, "day.makkah-ramadan-hijri-offset", "2026-02-17, the day before Ramadan 1447, with the rule on and a Hijri day offset of +1: the shifted calendar puts it in Ramadan, so Isha is Maghrib plus 120 minutes.",
    RAM, makkah, P("ummAlQura", ramadanIsha={"interval": {"minutes": 120, "hijriDayOffset": 1}}), {"type": "day", "day": "2026-02-17"})
add(F, "day.makkah-ramadan-angle-isha", "Makkah, Muslim World League with the Ramadan rule on, 2026-03-01: the rule replaces only an interval Isha, so the 17° Isha is unchanged.",
    RAM, makkah, P("muslimWorldLeague", ramadanIsha={"interval": {"minutes": 120, "hijriDayOffset": 0}}), {"type": "day", "day": "2026-03-01"})
IQ = {"rules": {"dhuhr": {"after": 20}}, "jumuah": {"after": 45}}
FRI = "RFC 0001 §4.3 rule 11 (never inferred from the weekday), §4.5 (the Jumu'ah rule applies only to a declared Jumu'ah); RFC 0002 §4.2 step 5 (observance .ordinary)"
add(F, "day.makkah-friday-dhuhr-ordinary", "Makkah, Umm al-Qura, Friday 2026-10-16, with iqama rules {dhuhr: after 20} and {jumuah: after 45}: Dhuhr stays ordinary, so the Dhuhr rule gives its iqama (12:26) and the Jumu'ah rule doesn't apply.",
    f"{FRI}; {REF}", makkah, UQ, {"type": "day", "day": "2026-10-16"}, iqama=IQ)
add(F, "state.makkah-friday-after-dhuhr", "State at 12:15 on Friday 2026-10-16 in Makkah with the same iqama rules: the ordinary Dhuhr (12:06) has just started until its iqama at 12:26.",
    f"{FRI}; RFC 0001 §4.7 (justStarted untilIqama); {REF}", makkah, UQ, {"type": "state", "at": local(makkah, 2026, 10, 16, 12, 15)}, iqama=IQ,
    statuses=["2026-10-16/dhuhr", "2026-10-16/asr"])

# clock-changes -------------------------------------------------------------------------------

F = "clock-changes"
DST = f"{R2}; RFC 0001 §4.1 (start(in:) with nextValid and earlier); {REF}"
ISNA = P("isna")
add(F, "day.london-spring-forward", "London, ISNA, 2026-03-29, when clocks go from 01:00 GMT to 02:00 BST: a complete day, every event on BST.",
    DST, london, ISNA, {"type": "day", "day": "2026-03-29"})
add(F, "day.london-fall-back", "London, ISNA, 2026-10-25, when clocks go back from 02:00 BST to 01:00 GMT: a complete day, every event on GMT.",
    DST, london, ISNA, {"type": "day", "day": "2026-10-25"})
add(F, "events.london-spring-forward-night", "Events from 18:00 GMT on 03-28 to 08:00 BST on 03-29 in London: 03-28's Maghrib and Isha, then 03-29's Fajr and sunrise; complete coverage across the change.",
    f"RFC 0001 §4.6; {DST}", london, ISNA, {"type": "events", "from": local(london, 2026, 3, 28, 18, 0), "through": local(london, 2026, 3, 29, 8, 0)})
add(F, "state.london-spring-forward-night", "State at 02:30 BST on 03-29 in London, just after the change: previous is 03-28's Isha, next 03-29's Fajr.",
    f"RFC 0001 §4.7; {DST}", london, ISNA, {"type": "state", "at": local(london, 2026, 3, 29, 2, 30)},
    statuses=["2026-03-28/isha", "2026-03-29/fajr"])
add(F, "day.new-york-spring-forward", "New York, ISNA, 2026-03-08, the spring-forward day: complete, every event on EDT.",
    DST, newyork, ISNA, {"type": "day", "day": "2026-03-08"})
add(F, "day.beirut-skipped-midnight", "Beirut, Muslim World League, 2026-03-29: clocks go from 00:00 to 01:00, so the day starts at 01:00 EEST. A complete day.",
    DST, beirut, MWL, {"type": "day", "day": "2026-03-29"})
add(F, "events.beirut-skipped-midnight", "Events from 21:00 on 03-28 to 06:00 on 03-29 in Beirut, across the skipped midnight: 03-29's Fajr only; complete coverage.",
    f"RFC 0001 §4.6; {DST}", beirut, MWL, {"type": "events", "from": local(beirut, 2026, 3, 28, 21, 0), "through": local(beirut, 2026, 3, 29, 6, 0)})

# state-and-refresh -----------------------------------------------------------------------------

F = "state-and-refresh"
RF = "RFC 0001 §4.8 (transitions, dates, lookahead bound start(civil(e) + 2))"
add(F, "refresh.kazan-early-fajr-night", "stateChanges from 20:00 on 06-19 to 04:00 on 06-20 in Kazan: Maghrib's approach (20:17), Maghrib (20:32) and its just-started end (20:47), the approach of Isha and of 06-20's Fajr (23:30), the two events at 23:45, the end of Fajr's just-started window at midnight, and sunrise (02:58). The entry at 23:45 already has 06-20's Fajr as previous.",
    f"{RF}; {LEADP}; {REF}", kazan, KAZAN, {"type": "refresh", "from": local(kazan, 2026, 6, 19, 20, 0), "through": local(kazan, 2026, 6, 20, 4, 0)},
    entries=list(range(0, 8)))
add(F, "refresh.tromso-polar-day", "stateChanges from 12:00 on 06-21 to 18:00 on 06-22 at Tromsø in polar day: unavailable until Dhuhr, available from Dhuhr through Asr, unavailable again from Asr (17:58) until 06-22's Dhuhr, and the same pattern on 06-22. Entries carry the polar windows as gaps.",
    f"{RF}; {POL}", tromso, MWL, {"type": "refresh", "from": local(tromso, 2026, 6, 21, 12, 0), "through": local(tromso, 2026, 6, 22, 18, 0)},
    entries=list(range(0, 8)))
add(F, "refresh.tromso-polar-night", "stateChanges from 06:00 to 18:00 on 12-21 at Tromsø in polar night: Fajr's approach and Fajr, after which previous is null (sunrise's window opens) while latestPrayer and nextPrayer stay known; Dhuhr starts an unavailable span (Asr and Maghrib missing) that ends at Isha (16:44).",
    f"{RF}; {POL}", tromso, MWL, {"type": "refresh", "from": local(tromso, 2026, 12, 21, 6, 0), "through": local(tromso, 2026, 12, 21, 18, 0)},
    entries=list(range(0, 8)))
add(F, "refresh.rovaniemi-missing-isha", "stateChanges from 22:00 on 06-01 to 04:00 on 06-02 at 66.5° N: Maghrib's approach and Maghrib (00:24), from which 06-01's missing Isha leaves the state unavailable until 06-02's Fajr (01:51), then sunrise.",
    f"{RF}; {NEXT}", rovaniemi, UQ, {"type": "refresh", "from": local(rovaniemi, 2026, 6, 1, 22, 0), "through": local(rovaniemi, 2026, 6, 2, 4, 0)},
    entries=list(range(0, 8)))
add(F, "refresh.oslo-rule-disabled-night", "stateChanges from 21:00 on 06-21 to 06:00 on 06-22 in Oslo with the rule disabled: Maghrib's approach and Maghrib (22:44), then an unavailable night until sunrise (03:54), when previous is sunrise and latestPrayer is still unknown (the night's windows hold prayers).",
    f"{RF}; {POL}", oslo, DIS, {"type": "refresh", "from": local(oslo, 2026, 6, 21, 21, 0), "through": local(oslo, 2026, 6, 22, 6, 0)},
    entries=list(range(0, 8)))
add(F, "refresh.kashgar-isha-after-midnight", "stateChanges from 21:00 on 06-21 to 06:00 on 06-22 in Kashgar: Maghrib (22:27), the approach of 06-21's Isha (00:04) and Isha itself at 00:19 on 06-22, then 06-22's Fajr (05:28).",
    f"{RF}; {R2}; {REF}", kashgar, MWL, {"type": "refresh", "from": local(kashgar, 2026, 6, 21, 21, 0), "through": local(kashgar, 2026, 6, 22, 6, 0)},
    entries=list(range(0, 8)))
add(F, "refresh.makkah-day-budget", "stateChanges over the whole of 2026-10-13 in Makkah with limit 8: the day has 17 dates, so the plan keeps the first 7 and is valid until the 8th, the end of Dhuhr's just-started window (12:22).",
    f"{RF}, budget; {R2}; {REF}", makkah, UQ, {"type": "refresh", "from": local(makkah, 2026, 10, 13, 0, 0), "through": local(makkah, 2026, 10, 14, 0, 0), "limit": 8},
    entries=[0, 6])
add(F, "state.kazan-early-fajr-unbounded-day", "State at 21:00 on 06-19 in Kazan with the default bound: next is 06-19's Isha (23:45); 06-20's Fajr, at the same instant, is upcoming, not next.",
    f"RFC 0001 §4.7; {LEADP}; {REF}", kazan, KAZAN, {"type": "state", "at": local(kazan, 2026, 6, 19, 21, 0)},
    statuses=["2026-06-19/maghrib", "2026-06-19/isha", "2026-06-20/fajr", "2026-06-20/sunrise"])
add(F, "state.london-fall-back-repeated-hour", "State at 01:00 GMT on 10-25 in London, inside the repeated hour after the clocks went back: previous is 10-24's Isha (19:21 BST), next 10-25's Fajr (05:09 GMT).",
    f"RFC 0001 §4.7; {DST}", london, ISNA, {"type": "state", "at": local(london, 2026, 10, 25, 0, 30) + 3600 * 1.5})
