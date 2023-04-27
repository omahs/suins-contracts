module suins::converter {

    use std::vector;
    use std::string::{Self, String};

    const REGISTRATION_FEE_PER_YEAR: u64 = 1000000;
    const EInvalidNumber: u64 = 601;

    public fun string_to_number(str: String): u64 {
        let bytes = string::bytes(&str);
        // count from 1 because Move doesn't have negative number atm
        let index = vector::length(bytes);
        let result: u64 = 0;
        let base = 1;

        while (index > 0) {
            let byte = *vector::borrow(bytes, index - 1);
            assert!(byte >= 0x30 && byte <= 0x39, EInvalidNumber); // 0-9
            result = result + ((byte as u64) - 0x30) * base;
            // avoid overflow if input is MAX_U64
            if (index != 1) base = base * 10;
            index = index - 1;
        };
        result
    }
}
