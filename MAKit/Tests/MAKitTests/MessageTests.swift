import Foundation
import Testing
@testable import MAKit

@Suite struct MessageTests {
    @Test func aReplyCarriesItsIdAndResult() throws {
        let msg = try MAMessage.parse(Data(#"{"message_id":"7","result":[1,2]}"#.utf8))
        #expect(msg.messageId == "7" && msg.event == nil)
        #expect(try JSONDecoder().decode([Int].self, from: try #require(msg.result)) == [1, 2])
    }

    @Test func anErrorReplyBecomesAnError() throws {
        let msg = try MAMessage.parse(Data(#"{"message_id":"8","error_code":5,"details":"nope"}"#.utf8))
        #expect(msg.error == MAError.server(code: 5, details: "nope"))
    }

    @Test func anEventIsRecognised() throws {
        let msg = try MAMessage.parse(Data(#"{"event":"queue_updated","object_id":"q1","data":{"state":"playing"}}"#.utf8))
        #expect(msg.event == "queue_updated" && msg.objectId == "q1" && msg.messageId == nil)
    }

    @Test func aCommandIsEncodedWithItsArguments() throws {
        let data = try MAMessage.command(id: "3", "players/cmd/volume_set", ["player_id": "p", "volume_level": 40])
        let obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["message_id"] as? String == "3" && obj["command"] as? String == "players/cmd/volume_set")
        let args = try #require(obj["args"] as? [String: Any])
        #expect(args["player_id"] as? String == "p" && args["volume_level"] as? Int == 40)
    }

    @Test func messageUrlConversionKeepsPortAndPath() throws {
        #expect(MAClient.socketURL(URL(string: "http://192.0.2.10:8095")!).absoluteString == "ws://192.0.2.10:8095/ws")
        #expect(MAClient.socketURL(URL(string: "https://ma.example/")!).absoluteString == "wss://ma.example/ws")
    }

    @Test func coverAddressesUseTheImageProxy() {
        let url = SharedStore.coverURL(server: URL(string: "http://h:8095")!, key: "abc", size: 256)
        #expect(url.absoluteString == "http://h:8095/imageproxy/abc?size=256")
    }
}
