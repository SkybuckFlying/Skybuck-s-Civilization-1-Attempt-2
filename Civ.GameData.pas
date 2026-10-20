unit Civ.GameData;

// Style: semantic-prefixes v2.0

interface

uses
    Civ.Types;

type
    TCivType = packed record
        Leader    : TCStr16;
        Plural    : TCStr16;
        Adjective : TCStr16;
        F0, F1, F2, F3, F4 : SmallInt;
    end;

    TAdvance = packed record
        Name    : TCStr20;
        Prereq1 : ShortInt;
        Prereq2 : ShortInt;
    end;

    TImprovement = packed record
        Name        : TCStr24;
        Cost        : SmallInt;
        Maintenance : SmallInt;
        Prereq      : SmallInt;
    end;

{ Civilizations / tribes — index 0 and 8 are empty placeholders.
  Entries 1..7 = first tribe per slot; 9..15 = alternate. }
function CivTable: PCivType;
function AdvanceTable: PAdvance;
function ImprovementTable: PImprovement;

implementation

const
    { From GAME.C civt[16]. Leader/plural/adjective preserved verbatim. }
    ConstCivs: array[0..15] of TCivType = (
        (Leader: ''             ; Plural: ''          ; Adjective: ''            ; F0: 0; F1: 0; F2: 0; F3: 36; F4: 36),
        (Leader: 'Caesar'       ; Plural: ''          ; Adjective: 'Roman'       ; F0: 0; F1: 1; F2: 1; F3: 24; F4: 10),
        (Leader: 'Hammurabi'    ; Plural: ''          ; Adjective: 'Babylonian'  ; F0:-1; F1:-1; F2: 1; F3: 28; F4: 14),
        (Leader: 'Frederick'    ; Plural: 'Germans'   ; Adjective: 'German'      ; F0: 1; F1:-1; F2: 1; F3: 32; F4: 18),
        (Leader: 'Ramesses'     ; Plural: ''          ; Adjective: 'Egyptian'    ; F0: 0; F1: 0; F2: 1; F3: 21; F4:  7),
        (Leader: 'Abe Lincoln'  ; Plural: ''          ; Adjective: 'American'    ; F0:-1; F1: 0; F2: 1; F3: 19; F4:  5),
        (Leader: 'Alexander'    ; Plural: ''          ; Adjective: 'Greek'       ; F0: 0; F1: 1; F2:-1; F3: 26; F4: 12),
        (Leader: 'M.Gandhi'     ; Plural: ''          ; Adjective: 'Indian'      ; F0:-1; F1:-1; F2: 0; F3: 31; F4: 17),
        (Leader: ''             ; Plural: ''          ; Adjective: ''            ; F0: 0; F1: 0; F2: 0; F3: 36; F4: 36),
        (Leader: 'Stalin'       ; Plural: ''          ; Adjective: 'Russian'     ; F0: 1; F1: 0; F2:-1; F3: 25; F4: 11),
        (Leader: 'Shaka'        ; Plural: ''          ; Adjective: 'Zulu'        ; F0: 1; F1: 0; F2: 0; F3: 22; F4:  8),
        (Leader: 'Napoleon'     ; Plural: 'French'    ; Adjective: 'French'      ; F0: 1; F1: 1; F2: 1; F3: 23; F4:  9),
        (Leader: 'Montezuma'    ; Plural: ''          ; Adjective: 'Aztec'       ; F0: 0; F1:-1; F2: 1; F3: 20; F4:  6),
        (Leader: 'Mao Tse Tung' ; Plural: 'Chinese'   ; Adjective: 'Chinese'     ; F0: 0; F1: 0; F2: 1; F3: 29; F4: 15),
        (Leader: 'Elizabeth I'  ; Plural: 'English'   ; Adjective: 'English'     ; F0: 0; F1: 1; F2: 0; F3: 27; F4: 13),
        (Leader: 'Genghis Khan' ; Plural: ''          ; Adjective: 'Mongol'      ; F0: 1; F1: 1; F2:-1; F3: 30; F4: 16)
    );

    { Abridged: names + prerequisites from GAME.C advances[72].
      Full 20-byte names are implied; shortened here for readability. }
    ConstAdvances: array[0..71] of TAdvance = (
        (Name:'Alphabet'             ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Code of Laws'         ; Prereq1: 0 ; Prereq2:-1),
        (Name:'Currency'             ; Prereq1:17 ; Prereq2:-1),
        (Name:'Atomic Theory'        ; Prereq1:51 ; Prereq2:11),
        (Name:'Democracy'            ; Prereq1:28 ; Prereq2:30),
        (Name:'Monarchy'             ; Prereq1:25 ; Prereq2: 1),
        (Name:'Astronomy'            ; Prereq1:26 ; Prereq2: 9),
        (Name:'MapMaking'            ; Prereq1: 0 ; Prereq2:-1),
        (Name:'Navigation'           ; Prereq1: 7 ; Prereq2: 6),
        (Name:'Mathematics'          ; Prereq1: 0 ; Prereq2:16),
        (Name:'Medicine'             ; Prereq1:28 ; Prereq2:24),
        (Name:'Physics'              ; Prereq1: 9 ; Prereq2: 8),
        (Name:'Engineering'          ; Prereq1:33 ; Prereq2:45),
        (Name:'University'           ; Prereq1: 9 ; Prereq2:28),
        (Name:'Magnetism'            ; Prereq1: 8 ; Prereq2:11),
        (Name:'Electronics'          ; Prereq1:12 ; Prereq2:54),
        (Name:'Masonry'              ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Bronze Working'       ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Iron Working'         ; Prereq1:17 ; Prereq2:-1),
        (Name:'Bridge Building'      ; Prereq1:18 ; Prereq2:45),
        (Name:'Invention'            ; Prereq1:12 ; Prereq2:30),
        (Name:'Computers'            ; Prereq1: 9 ; Prereq2:15),
        (Name:'Writing'              ; Prereq1: 0 ; Prereq2:-1),
        (Name:'Steam Engine'         ; Prereq1:11 ; Prereq2:20),
        (Name:'Trade'                ; Prereq1: 2 ; Prereq2: 1),
        (Name:'Ceremonial Burial'    ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Mysticism'            ; Prereq1:25 ; Prereq2:-1),
        (Name:'Nuclear Fission'      ; Prereq1:41 ; Prereq2: 3),
        (Name:'Philosophy'           ; Prereq1:26 ; Prereq2:30),
        (Name:'Religion'             ; Prereq1:28 ; Prereq2:22),
        (Name:'Literacy'             ; Prereq1:22 ; Prereq2: 1),
        (Name:'Horseback Riding'     ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Feudalism'            ; Prereq1:16 ; Prereq2: 5),
        (Name:'The Wheel'            ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Gunpowder'            ; Prereq1:20 ; Prereq2:18),
        (Name:'Industrialization'    ; Prereq1:49 ; Prereq2:53),
        (Name:'Chemistry'            ; Prereq1:13 ; Prereq2:10),
        (Name:'Combustion'           ; Prereq1:55 ; Prereq2:56),
        (Name:'Flight'               ; Prereq1:37 ; Prereq2:11),
        (Name:'Advanced Flight'      ; Prereq1:38 ; Prereq2:54),
        (Name:'Space Flight'         ; Prereq1:21 ; Prereq2:46),
        (Name:'Mass Production'      ; Prereq1:58 ; Prereq2:47),
        (Name:'Pottery'              ; Prereq1:-1 ; Prereq2:-1),
        (Name:'Communism'            ; Prereq1:28 ; Prereq2:35),
        (Name:'The Republic'         ; Prereq1: 1 ; Prereq2:30),
        (Name:'Construction'         ; Prereq1:16 ; Prereq2: 2),
        (Name:'Rocketry'             ; Prereq1:39 ; Prereq2:15),
        (Name:'The Corporation'      ; Prereq1:53 ; Prereq2:35),
        (Name:'Metallurgy'           ; Prereq1:34 ; Prereq2:13),
        (Name:'RailRoad'             ; Prereq1:23 ; Prereq2:19),
        (Name:'Nuclear Power'        ; Prereq1:27 ; Prereq2:15),
        (Name:'Theory of Gravity'    ; Prereq1: 6 ; Prereq2:13),
        (Name:'Steel'                ; Prereq1:48 ; Prereq2:35),
        (Name:'Banking'              ; Prereq1:24 ; Prereq2:44),
        (Name:'Electricity'          ; Prereq1:48 ; Prereq2:14),
        (Name:'Refining'             ; Prereq1:36 ; Prereq2:47),
        (Name:'Explosives'           ; Prereq1:34 ; Prereq2:36),
        (Name:'SuperConductor'       ; Prereq1:60 ; Prereq2:41),
        (Name:'Automobile'           ; Prereq1:37 ; Prereq2:52),
        (Name:'Genetic Engineering'  ; Prereq1:10 ; Prereq2:47),
        (Name:'Plastics'             ; Prereq1:55 ; Prereq2:40),
        (Name:'Recycling'            ; Prereq1:41 ; Prereq2: 4),
        (Name:'Chivalry'             ; Prereq1:32 ; Prereq2:31),
        (Name:'Robotics'             ; Prereq1:60 ; Prereq2:21),
        (Name:'Conscription'         ; Prereq1:44 ; Prereq2:56),
        (Name:'Labor Union'          ; Prereq1:41 ; Prereq2:43),
        (Name:'Fusion Power'         ; Prereq1:50 ; Prereq2:57),
        (Name:'1'                    ; Prereq1:127; Prereq2:127),
        (Name:'2'                    ; Prereq1:127; Prereq2:127),
        (Name:'3'                    ; Prereq1:127; Prereq2:127),
        (Name:'4'                    ; Prereq1:127; Prereq2:127),
        (Name:'Future Tech.'         ; Prereq1:127; Prereq2:127)
    );

    { Abridged from GAME.C improvements[46]; first 24 essential names. }
    ConstImprovements: array[0..45] of TImprovement = (
        (Name:'NONE';              Cost: 8; Maintenance:0; Prereq:-1),
        (Name:'Palace';            Cost:20; Maintenance:5; Prereq:16),
        (Name:'Barracks';          Cost: 4; Maintenance:0; Prereq:-1),
        (Name:'Granary';           Cost: 6; Maintenance:1; Prereq:42),
        (Name:'Temple';            Cost: 4; Maintenance:1; Prereq:25),
        (Name:'MarketPlace';       Cost: 8; Maintenance:1; Prereq: 2),
        (Name:'Library';           Cost: 8; Maintenance:1; Prereq:22),
        (Name:'Courthouse';        Cost: 8; Maintenance:1; Prereq: 1),
        (Name:'City Walls';        Cost:12; Maintenance:2; Prereq:16),
        (Name:'Aqueduct';          Cost:12; Maintenance:2; Prereq:45),
        (Name:'Bank';              Cost:12; Maintenance:3; Prereq:53),
        (Name:'Cathedral';         Cost:16; Maintenance:3; Prereq:29),
        (Name:'University';        Cost:16; Maintenance:3; Prereq:13),
        (Name:'Mass Transit';      Cost:16; Maintenance:4; Prereq:41),
        (Name:'Colosseum';         Cost:10; Maintenance:4; Prereq:45),
        (Name:'Factory';           Cost:20; Maintenance:4; Prereq:35),
        (Name:'Mfg. Plant';        Cost:32; Maintenance:6; Prereq:63),
        (Name:'SDI Defense';       Cost:20; Maintenance:4; Prereq:57),
        (Name:'Recycling Cntr.';   Cost:20; Maintenance:2; Prereq:61),
        (Name:'Power Plant';       Cost:16; Maintenance:4; Prereq:55),
        (Name:'Hydro Plant';       Cost:24; Maintenance:4; Prereq:15),
        (Name:'Nuclear Plant';     Cost:16; Maintenance:2; Prereq:50),
        (Name:'SS Structural';     Cost: 8; Maintenance:0; Prereq:40),
        (Name:'SS Component';      Cost:16; Maintenance:0; Prereq:60),
        (Name:'SS Module';         Cost:32; Maintenance:0; Prereq:63),
        (Name:'Pyramids';          Cost:30; Maintenance:0; Prereq:16),
        (Name:'Hanging Gardens';   Cost:30; Maintenance:0; Prereq:42),
        (Name:'Colossus';          Cost:20; Maintenance:0; Prereq:17),
        (Name:'Lighthouse';        Cost:20; Maintenance:0; Prereq: 7),
        (Name:'Great Library';     Cost:30; Maintenance:0; Prereq:30),
        (Name:'Oracle';            Cost:30; Maintenance:0; Prereq:26),
        (Name:'Great Wall';        Cost:30; Maintenance:0; Prereq:16),
        (Name:'Magellan''s Expedition'; Cost:40; Maintenance:0; Prereq: 8),
        (Name:'Michelangelo''s Chapel'; Cost:30; Maintenance:0; Prereq:29),
        (Name:'Copernicus'' Observatory'; Cost:30; Maintenance:0; Prereq: 6),
        (Name:'Shakespeare''s Theatre'; Cost:40; Maintenance:0; Prereq:10),
        (Name:'Isaac Newton''s College'; Cost:40; Maintenance:0; Prereq:51),
        (Name:'J.S.Bach''s Cathedral'; Cost:40; Maintenance:0; Prereq:29),
        (Name:'Darwin''s Voyage';  Cost:30; Maintenance:0; Prereq:49),
        (Name:'Hoover Dam';        Cost:60; Maintenance:0; Prereq:15),
        (Name:'Women''s Suffrage'; Cost:60; Maintenance:0; Prereq:35),
        (Name:'Manhattan Project'; Cost:60; Maintenance:0; Prereq:27),
        (Name:'United Nations';    Cost:60; Maintenance:0; Prereq:43),
        (Name:'Apollo Program';    Cost:60; Maintenance:0; Prereq:40),
        (Name:'SETI Program';      Cost:60; Maintenance:0; Prereq:21),
        (Name:'Cure for Cancer';   Cost:60; Maintenance:0; Prereq:59)
    );

function CivTable: PCivType;
begin
    Result := @ConstCivs[0];
end;

function AdvanceTable: PAdvance;
begin
    Result := @ConstAdvances[0];
end;

function ImprovementTable: PImprovement;
begin
    Result := @ConstImprovements[0];
end;

end.