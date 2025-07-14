object "RewardAccumulation" {
    code {
        // periodTimestamp init : periodTimestamp.push(block.timestamp)
        let periodTimestampSlot := 5 // periodTimestamp() must return 5
        sstore(periodTimestampSlot, 0x01)
        mstore(0x00, periodTimestampSlot)
        let firstElSlot := keccak256(0x00, 0x20)
        sstore(firstElSlot, timestamp())

        // integrateInvSupply init : integrateInvSupply.push(0)
        let integrateInvSupplySlot := 6 // integrateInvSupply() must return 6
        sstore(integrateInvSupplySlot, 0x01)
        mstore(0x00, integrateInvSupplySlot)
        firstElSlot := keccak256(0x00, 0x20)
        sstore(firstElSlot, 0x00)

        // Runtime code size
        let runtimeSize := datasize("runtime")
        
        // Copy runtime code to memory
        datacopy(0, dataoffset("runtime"), runtimeSize)

        // Append the immutable `weight = 5e17 (hex 0x6f05b59d3b20000)` at the end of runtime code
        mstore(runtimeSize, 0x6f05b59d3b20000)

        // Append the immutable `rate = 1e18 (hex 0xde0b6b3a7640000)` at the end of (runtime code + rate)
        mstore(add(runtimeSize, 0x20), 0xde0b6b3a7640000)


        // return whole runtime bytecode with immutables
        return(0, add(runtimeSize, 0x40))
    }

    object "runtime" {        
        code {
            // Protection against sending Ether
            require(iszero(callvalue()))
            
            /* ---------- Functions dispatcher ----------- */

            switch selector()
            // updateWorkingBalance(address,uint256,uint256,uint256,uint256)
            case 0xfe0aa103 {
                updateWorkingBalance()
            }
            // getBoostFactor(address)
            case 0xb10fb7aa {
                getBoostFactor()
            }
            // checkpoint(address)
            case 0xa972985e {
                checkpoint()
            }
            // getRate()
            case 0x679aefce {
                getRate()
            }
            // getWeight()
            case 0xa9b4b780 {
                getWeight()
            }
            // getUserWb(address)
            case 0xeaa0e30e {
                getUserWb()
            }
            // getWorkingSupply()
            case 0x0b716148 {
                getWorkingSupply()
            }
            // getUserReward(address)
            case 0xc75ebb82 {
                getUserReward()
            }
            // getPeriodTimestamp(uint256)
            case 0xbecc653b {
                getPeriodTimestamp()
            }
            default {
                revert (0,0)
            }

            /* ---------- Functions ----------- */

            function getRate() {
                let RATE_OFFSET := 0x0000000000000000000000000000000000000000000000000000000000000020
                let rate := getImmutable(RATE_OFFSET, 0x00)
                returnUint(rate)
            }

            function getWeight() {
                let WEIGHT_OFFSET := 0x0000000000000000000000000000000000000000000000000000000000000040
                let weight := getImmutable(WEIGHT_OFFSET, 0x00)
                returnUint(weight)
            }

            function getUserWb() {
                let user := decodeAsAddress(0)
                let workingBalancesSlot := workingBalances()
                let hashSlot := getSlotFromKeys(0x00, workingBalancesSlot, user)
                let wb := sload(hashSlot)
                returnUint(wb)
            }

            function getWorkingSupply() {
                let ws := sload(workingSupply())
                returnUint(ws)
            }

            function getUserReward() {
                let user := decodeAsAddress(0)
                let integrateFractionSlot := integrateFraction()
                let hashSlot := getSlotFromKeys(0x00, integrateFractionSlot, user)
                let ur := sload(hashSlot)
                returnUint(ur)
            }

            function getPeriodTimestamp() {
                let index := decodeAsUint(0)
                mstore(0x00, periodTimestamp())
                let slotHash := add(keccak256(0x00, 0x20), index)
                let timestmp := sload(slotHash)
                returnUint(timestmp)
            }

            function getBoostFactor() {
                let TOKENLESS_PRODUCTION := 0x28 // 40 in dec
                let user := decodeAsAddress(0)

                let workingBalancesSlot := workingBalances()
                let wbHashSlot := getSlotFromKeys(0x00, workingBalancesSlot, user)
                let wb := sload(wbHashSlot)

                let balanceOfSlot := balanceOf()
                let boHashSlot := getSlotFromKeys(0x00, balanceOfSlot, user)
                let bo := sload(boHashSlot)

                returnUint(div(wb, div(mul(bo, TOKENLESS_PRODUCTION), 0x64)))
            }

            function updateWorkingBalance() {
                let TOKENLESS_PRODUCTION := 0x28 // 40 in dec
                let user := decodeAsAddress(0)
                let userLiquidity := decodeAsUint(1)
                let totalLiquidity := decodeAsUint(2)
                let boostBalance := decodeAsUint(3)
                let boostTotal := decodeAsUint(4)

                let limit := div(mul(TOKENLESS_PRODUCTION, userLiquidity), 0x64)

                if gt(boostBalance, 0) {
                    limit := add(limit, div(mul(div(mul(totalLiquidity, boostBalance), boostTotal), sub(0x64, TOKENLESS_PRODUCTION)), 0x64))
                }

                if lt(userLiquidity, limit) {
                    limit := userLiquidity
                }

                let workingBalancesSlot := workingBalances()
                let wbHashSlot := getSlotFromKeys(0x00, workingBalancesSlot, user)
                let oldWBalance := sload(wbHashSlot)
                sstore(wbHashSlot, limit)
                sstore(workingSupply(), sub(add(sload(workingSupply()), limit), oldWBalance))
            }

            function checkpoint() {
                let WEEK := 0x93a80 // 604800 in dec
                let TOKENLESS_PRODUCTION := 0x28 // 40 in dec
                let RATE_OFFSET := 0x0000000000000000000000000000000000000000000000000000000000000020
                let WEIGHT_OFFSET := 0x0000000000000000000000000000000000000000000000000000000000000040
                let user := decodeAsAddress(0)

                let _period := sload(period())
                mstore(0x00, periodTimestamp())
                let _periodTime := sload(add(keccak256(0x00, 0x20), _period))
                let _workingBalance := sload(getSlotFromKeys(0x00, workingBalances(), user))
                let _workingSupply := sload(workingSupply())
                mstore(0x00, integrateInvSupply())
                let _integrateInvSupply := sload(add(keccak256(0x00, 0x20), _period))

                if gt(timestamp(), _periodTime) {
                    let prevWeekTime := _periodTime
                    let prevWeekTimePlusWeek := mul(div(add(prevWeekTime, WEEK), WEEK), WEEK)
                    let weekTime := timestamp()
                    if lt(prevWeekTimePlusWeek, timestamp()) {
                        weekTime := prevWeekTimePlusWeek
                    }

                    let rate := getImmutable(RATE_OFFSET, 0x00)
                    let weight := getImmutable(WEIGHT_OFFSET, 0x00)

                    for { let i := 0 } lt(i, 0x1f4) { i := add(i, 0x01) } {
                        let dt := sub(weekTime, prevWeekTime)

                        if gt(_workingSupply, 0) {
                            _integrateInvSupply := add(_integrateInvSupply, div(mul(dt, mul(rate, weight)), _workingSupply))
                        }

                        if eq(weekTime, timestamp()) {
                            break
                        }

                        prevWeekTime := weekTime
                        prevWeekTimePlusWeek := add(weekTime, WEEK)
                        weekTime := timestamp()
                        if lt(prevWeekTimePlusWeek, timestamp()) {
                            weekTime := prevWeekTimePlusWeek
                        }
                    }
                }

                sstore(period(), add(0x01, _period))
                let oldPeriodTimestampLength := sload(periodTimestamp())
                sstore(periodTimestamp(), add(0x01, oldPeriodTimestampLength))
                mstore(0x00, periodTimestamp())
                sstore(add(keccak256(0x00, 0x20), oldPeriodTimestampLength), timestamp())
                let oldIntegrateInvSupplyLength := sload(integrateInvSupply())
                sstore(integrateInvSupply(), add(0x01, oldIntegrateInvSupplyLength))
                mstore(0x00, integrateInvSupply())
                sstore(add(keccak256(0x00, 0x20), oldIntegrateInvSupplyLength), _integrateInvSupply)

                // update user's integral
                let integrateFractionSlot := getSlotFromKeys(0x00, integrateFraction(), user)
                let oldIntegrateFraction := sload(integrateFractionSlot)
                let integrateInvSupplyOfSlot := getSlotFromKeys(0x00, integrateInvSupplyOf(), user) 
                sstore(integrateFractionSlot, add(div(mul(_workingBalance, sub(_integrateInvSupply, sload(integrateInvSupplyOfSlot))), 0xde0b6b3a7640000), oldIntegrateFraction))
                sstore(integrateInvSupplyOfSlot, _integrateInvSupply)
                sstore(getSlotFromKeys(0x00, integrateCheckpointOf(), user), timestamp())
            }

            /* ---------- Storage slots ----------- */
            
            function workingBalances() -> p { p := 0 }
            function workingSupply() -> p { p := 1 }
            function balanceOf() -> p { p := 2 }
            function totalSupply() -> p { p := 3 }
            function period() -> p { p := 4 }
            function periodTimestamp() -> p { p := 5 }
            function integrateInvSupply() -> p { p := 6 }
            function integrateInvSupplyOf() -> p { p := 7 }
            function integrateCheckpointOf() -> p { p :=8 }
            function integrateFraction() -> p { p := 9 }

            /* ---------- Calldata functions ----------- */

            function selector() -> s {
                s := div(calldataload(0), 0x100000000000000000000000000000000000000000000000000000000)
            }

            function decodeAsUint(offset) -> v {
                let positionInCalldata := add(4, mul(offset, 0x20))
                if lt(calldatasize(), add(positionInCalldata, 0x20)) {
                    revert (0,0)
                }
                v := calldataload(positionInCalldata)
            }

            function decodeAsAddress(offset) -> v {
                v := decodeAsUint(offset)
                if iszero(iszero(and(v, not(0xffffffffffffffffffffffffffffffffffffffff)))) {
                    revert(0, 0)
                }
            }

            function returnUint(v) {
                mstore(0, v)
                return (0, 0x20)
            }

            /* ---------- Utils functions ----------- */

            function require(condition) {
                if iszero(condition) { revert(0, 0) }
            }

            function getImmutable(offset_end, free_memory) -> imValue {
                let offsetCode := sub(codesize(), offset_end)
                codecopy(free_memory, offsetCode, 0x20)
                imValue := mload(free_memory)
            }

            function getSlotFromKeys(free_memory, slot, key) -> hashSlot {
                mstore(add(free_memory, 0x20), slot)
                mstore(free_memory, key)
                hashSlot := keccak256(free_memory, 0x40)
            }
        }
    }
}