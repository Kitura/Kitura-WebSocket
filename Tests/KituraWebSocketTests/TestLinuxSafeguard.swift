/**
 * Copyright IBM Corporation 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

#if os(OSX)
    import XCTest
    
    class TestLinuxSafeguard: XCTestCase {
        func testVerifyLinuxTestCount() {
            var linuxCount: Int
            var darwinCount: Int
            
            // BasicTests
            linuxCount = BasicTests.allTests.count
            darwinCount = Int(BasicTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from BasicTests.allTests")
            
            // ComplexTests
            linuxCount = ComplexTests.allTests.count
            darwinCount = Int(ComplexTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from ComplexTests.allTests")
            
            // ProtocolErrorTests
            linuxCount = ProtocolErrorTests.allTests.count
            darwinCount = Int(ProtocolErrorTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from ProtocolErrorTests.allTests")
            
            // UpgradeErrors
            linuxCount = UpgradeErrors.allTests.count
            darwinCount = Int(UpgradeErrors.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from UpgradeErrors.allTests")
        }
    }
#endif
