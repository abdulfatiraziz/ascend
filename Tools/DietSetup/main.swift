import AscendCore
import Foundation

struct Setup: Decodable { var plan: DietPlan; var weekdayLimits: [Int:Double]? }
guard CommandLine.arguments.count == 3 else { fatalError("Usage: AscendDietSetup <tracker.json> <diet-setup.json>; close Ascend first") }
let url=URL(fileURLWithPath:CommandLine.arguments[1]),setupURL=URL(fileURLWithPath:CommandLine.arguments[2])
let original=try Data(contentsOf:url)
var document=try JSONDecoder().decode(TrackerDocument.self,from:original)
try document.validate()
let setup=try JSONDecoder().decode(Setup.self,from:Data(contentsOf:setupURL))
let today=TrackerEngine(document:document).key(Date())
try document.applyDietPlan(setup.plan,weekdayLimits:setup.weekdayLimits,today:today)
let encoder=JSONEncoder();encoder.userInfo[TrackerDocument.omitHealth]=true;encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
let bytes=try encoder.encode(document)
let verified=try JSONDecoder().decode(TrackerDocument.self,from:bytes);try verified.validate()
guard try Data(contentsOf:url)==original else {fatalError("Tracker changed while preparing setup; nothing was written")}
let backup=url.deletingLastPathComponent().appendingPathComponent("tracker-before-diet-\(UUID().uuidString).json")
try original.write(to:backup,options:.atomic)
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:backup.path)
try bytes.write(to:url,options:.atomic)
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
print("Validated diet setup saved. Existing notes and habit IDs preserved; rollback backup created beside tracker.json.")
