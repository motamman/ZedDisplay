import '../engine.dart';
import 'depare01.dart';
import 'depcnt02.dart';
import 'lights05.dart';
import 'obstrn04.dart';
import 'quapos01.dart';
import 'resare02.dart';
import 'restrn01.dart';
import 'slcons03.dart';
import 'soundg02.dart';
import 'topmar01.dart';
import 'wrecks02.dart';

/// The canonical registry of conditional-symbology procedures shipped
/// with `s52_dart`. Hand this to [S52StyleEngine.csProcedures] to get
/// the full ported S-52 behaviour.
///
/// Registry grows as procedures are ported. A consumer that wants a
/// subset — or wants to swap in a locally-patched implementation —
/// can start from [standardCsProcedures] and `{...map, 'NAME': custom}`.
const Map<String, S52CsProcedure> standardCsProcedures = {
  'LIGHTS05': lights05,
  // Freeboard's evalCS aliases DEPARE01 and DEPARE02 to the same
  // handler. Real lookup rows use either name.
  'DEPARE01': depare01,
  'DEPARE02': depare01,
  'DEPCNT02': depcnt02,
  'SOUNDG02': soundg02,
  'OBSTRN04': obstrn04,
  'WRECKS02': wrecks02,
  'SLCONS03': slcons03,
  'TOPMAR01': topmar01,
  'QUAPOS01': quapos01,
  'RESTRN01': restrn01,
  // Freeboard's evalCS also aliases RESARE01 and RESARE02 to one
  // handler; register both here.
  'RESARE01': resare02,
  'RESARE02': resare02,
};
