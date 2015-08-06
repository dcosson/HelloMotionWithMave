//
//  MAVEABPerson.m
//  MaveSDKDevApp
//
//  Created by dannycosson on 9/25/14.
//  Copyright (c) 2015 Mave Technologies, Inc. All rights reserved.
//

#import "MAVEABPerson.h"
#import "MaveConstants.h"
#import "MAVEClientPropertyUtils.h"
#import "MAVEMerkleTreeHashUtils.h"
#import "NBPhoneNumber.h"
#import "NBPhoneNumberUtil.h"
#import "MAVEABUtils.h"

@implementation MAVEABPerson

- (instancetype) init {
    if (self = [super init]) {
        self.hashedRecordID = [[self class] computeHashedRecordID:0];
    }
    return self;
}

- (instancetype)initFromABRecordRef:(ABRecordRef)record {
    if (self = [self init]) {
        @try {
            int32_t rid = ABRecordGetRecordID(record);
            self.recordID = rid;
            self.firstName = (__bridge_transfer NSString *)ABRecordCopyValue(record, kABPersonFirstNameProperty);
            self.lastName = (__bridge_transfer NSString *)ABRecordCopyValue(record, kABPersonLastNameProperty);
            if (self.firstName == nil && self.lastName ==nil) {
                return nil;
            }
            [self setPhoneNumbersFromABRecordRef:record];
            [self setEmailAddressesFromABRecordRef:record];
            if ([self.phoneNumbers count] == 0 && [self.emailAddresses count] == 0){
                return nil;
            }
        }
        @catch (NSException *exception) {
            self = nil;
        }
    }
    return self;
}

- (void)setRecordID:(int32_t)recordID {
    // record ID is actually a 32 bit integer
    _recordID = recordID;
    self.hashedRecordID = [[self class] computeHashedRecordID:recordID];
}

- (void)setSelected:(BOOL)selected {
    if (selected) {
        [self selectBestContactIdentifierIfNoneSelected];
    } else {
        for (MAVEContactIdentifierBase *rec in self.allContactIdentifiers) {
            if (rec.selected) {
                rec.selected = NO;
            }
        }
    }
    _selected = selected;
}


///
/// Serialization methods for sending over wire
///
- (NSDictionary *)toJSONDictionary {
    NSArray *tupleArray = [self toJSONTupleArray];
    NSMutableDictionary *output = [NSMutableDictionary dictionaryWithCapacity:[tupleArray count]];
    for (NSArray *tuple in tupleArray) {
        [output setValue:tuple[1] forKey:tuple[0]];
    }
    return [NSDictionary dictionaryWithDictionary:output];
}

- (NSArray *)toJSONTupleArray {
    // Needs to be in the expected order, which is the following
    return @[
        @[@"record_id", [[NSNumber alloc]initWithInteger:self.recordID]],
        @[@"hashed_record_id", @(self.hashedRecordID)],
        @[@"first_name", self.firstName ? self.firstName : [NSNull null]],
        @[@"last_name", self.lastName ? self.lastName : [NSNull null]],
        @[@"phone_numbers", [self.phoneNumbers count] > 0 ? self.phoneNumbers : @[]],
        @[@"phone_number_labels", [self.phoneNumberLabels count] > 0 ? self.phoneNumberLabels : @[]],
        @[@"email_addresses", [self.emailAddresses count] > 0 ? self.emailAddresses : @[]],
    ];
}

- (NSDictionary *)toJSONDictionaryIncludingSuggestionsMetadata {
    NSDictionary *baseDict = [self toJSONDictionary];
    NSMutableDictionary *newDict = [NSMutableDictionary dictionaryWithDictionary:baseDict];
    [newDict setValue:@(self.isSuggestedContact) forKey:@"is_suggested_contact"];
    [newDict setValue:@(self.selectedFromSuggestions) forKey:@"selected_from_suggestions"];
    return [NSDictionary dictionaryWithDictionary:newDict];
}

- (uint64_t)merkleTreeDataKey {
    return self.hashedRecordID;
}

- (id)merkleTreeSerializableData {
    return [self toJSONTupleArray];
}

- (void)setPhoneNumbersFromABRecordRef:(ABRecordRef) record{
    ABMultiValueRef phoneMultiValue = ABRecordCopyValue(record, kABPersonPhoneProperty);
    NSUInteger numPhones = ABMultiValueGetCount(phoneMultiValue);
    NSMutableArray *phoneNumbers = [[NSMutableArray alloc] initWithCapacity:numPhones];
    NSMutableArray *phoneNumberLabels = [[NSMutableArray alloc] initWithCapacity:numPhones];
    NSMutableArray *phoneNumberObjects = [[NSMutableArray alloc] initWithCapacity:numPhones];
    
    NSString *pn; NSString *label;
    NSInteger insertIndex = 0;
    for (NSUInteger readIndex=0; readIndex < numPhones; readIndex++) {
        pn = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(phoneMultiValue, readIndex);
        pn = [[self class] normalizePhoneNumber:pn];
        if (pn != nil) {
            [phoneNumbers insertObject:pn atIndex: insertIndex];
            label = (__bridge_transfer NSString *) ABMultiValueCopyLabelAtIndex(phoneMultiValue, readIndex);
            if (label == nil) {
                label = (__bridge_transfer NSString *) kABPersonPhoneOtherFAXLabel;
            }
            [phoneNumberLabels insertObject:label atIndex:insertIndex];

            MAVEContactPhoneNumber *pnObj = [[MAVEContactPhoneNumber alloc] initWithValue:pn andLabel:label];
            if (pnObj) {
                [phoneNumberObjects addObject:pnObj];
            }
            insertIndex += 1;
        }
    }
    if (phoneMultiValue != NULL) CFRelease(phoneMultiValue);
    self.phoneNumbers = phoneNumbers;
    self.phoneNumberLabels = phoneNumberLabels;
    self.phoneObjects = [NSArray arrayWithArray:phoneNumberObjects];
}

- (void)setEmailAddressesFromABRecordRef:(ABRecordRef) record{
    ABMultiValueRef emailMultiValue = ABRecordCopyValue(record, kABPersonEmailProperty);
    NSUInteger numEmails = ABMultiValueGetCount(emailMultiValue);
    NSMutableArray *emailAddresses = [[NSMutableArray alloc] initWithCapacity:numEmails];
    NSMutableArray *emailObjects = [[NSMutableArray alloc] initWithCapacity:numEmails];
    for (NSUInteger i=0; i < numEmails; i++) {
        NSString *emailAddress = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(emailMultiValue, i);
        if (emailAddress) {
            [emailAddresses addObject:emailAddress];
            MAVEContactEmail *emailObj = [[MAVEContactEmail alloc] initWithValue:emailAddress];
            [emailObjects addObject:emailObj];
        }
    }
    if (emailMultiValue != NULL) CFRelease(emailMultiValue);
    self.emailAddresses = [NSArray arrayWithArray:emailAddresses];
    self.emailObjects = [NSArray arrayWithArray:emailObjects];
}


+ (uint64_t)computeHashedRecordID:(ABRecordID)recordID {
    NSData *recIDData = [MAVEMerkleTreeHashUtils dataFromInt32:recordID];
    NSData *hashedTruncatedData = [MAVEMerkleTreeHashUtils md5Hash:recIDData
                                                  truncatedToBytes:sizeof(uint64_t)];
    return [MAVEMerkleTreeHashUtils UInt64FromData:hashedTruncatedData];
}

- (UIImage *)picture {
    if (_picture) {
        return _picture;
    } else {
        return [MAVEABUtils getImageLookingUpPersonByRecordID:self.recordID];
    }
}

- (NSString *)firstLetter {
    NSString *compName = [self nameForCompareNames];
    if ([compName length] < 1) {
        return @"";
    }
    NSString *letter = [compName substringToIndex:1];
    letter = [letter uppercaseString];
    return letter;
}

- (NSString *)fullName {
    NSString *name = nil;
    if (self.firstName != nil && self.lastName != nil) {
        name = [NSString stringWithFormat:@"%@ %@", self.firstName, self.lastName];
    } else if (self.firstName != nil) {
        name = self.firstName;
    } else if (self.lastName != nil) {
        name = self.lastName;
    }
    return name;
}

- (NSString *)initials {
    NSString *returnval = @"";
    if (self.firstName && [self.firstName length] > 0) {
        returnval = [returnval stringByAppendingString:[self.firstName substringWithRange:NSMakeRange(0, 1)]];
    }
    if (self.lastName && [self.lastName length] > 0) {
        returnval = [returnval stringByAppendingString:[self.lastName substringWithRange:NSMakeRange(0, 1)]];
    }
    return returnval;
}

- (NSArray *)allContactIdentifiers {
    NSArray *result = @[];
    result = [result arrayByAddingObjectsFromArray:self.phoneObjects];
    result = [result arrayByAddingObjectsFromArray:self.emailObjects];
    return result;
}

- (NSArray *)rankedContactIdentifiersIncludeEmails:(BOOL)includeEmails includePhones:(BOOL)includePhones {
    NSArray *unranked = @[];
    if (includePhones && includeEmails) {
        unranked = [self allContactIdentifiers];
    } else if (includePhones) {
        unranked = [self phoneObjects];
    } else if (includeEmails) {
        unranked = [self emailObjects];
    }
    return [unranked sortedArrayUsingSelector:@selector(compareContactIdentifiers:)];
}

- (NSArray *)selectedContactIdentifiers {
    NSMutableArray *output = [[NSMutableArray alloc] initWithCapacity:[self.allContactIdentifiers count]];
    for (MAVEContactIdentifierBase *rec in [self allContactIdentifiers]) {
        if (rec.selected) {
            [output addObject:rec];
        }
    }
    return [NSArray arrayWithArray:output];
}

- (BOOL)isAtLeastOneContactIdentifierSelected {
    BOOL returnval = NO;
    for (MAVEContactIdentifierBase *rec in [self allContactIdentifiers]) {
        if (rec.selected) {
            returnval = YES;
            break;
        }
    }
    return returnval;
}

- (void)selectBestContactIdentifierIfNoneSelected {
    if (![self isAtLeastOneContactIdentifierSelected]) {
        NSArray *rankedIdentifiers = [self rankedContactIdentifiersIncludeEmails:YES includePhones:YES];
        if ([rankedIdentifiers count] > 0) {
            MAVEContactIdentifierBase *topRec = [rankedIdentifiers objectAtIndex:0];
            topRec.selected = YES;
        }
    }
}

// Use the libPhoneNumber-iOS library to normalize phone numbers based on the
// device's current country code.
//
// Also apply some filters to require area codes in various countries
+ (NSString *)normalizePhoneNumber:(NSString *)phoneNumber {
    NBPhoneNumberUtil *phoneNumberUtil = [[NBPhoneNumberUtil alloc] init];

    // Find current country code for device
    NSString *countryCode = [MAVEClientPropertyUtils countryCode];
    if ((id)countryCode == [NSNull null] || [countryCode length] == 0) {
        countryCode = @"US";
    }

    // Parse the phone numbers
    NSError *parseError = nil;
    NBPhoneNumber *pnObject = [phoneNumberUtil parse:phoneNumber
                                       defaultRegion:countryCode
                                               error:&parseError];
    if (parseError) {
        MAVEDebugLog(@"Error %@ parsing phone number %@", parseError, phoneNumber);
        return nil;
    }

    // Filter ones we don't want to use. In the US, this is any 7 digit numbers because
    // those don't have an area code
    NSDictionary *nationalNumberMinLengths = @{
        @1: @10,
    };
    NSString *nationalNumber = [phoneNumberUtil getNationalSignificantNumber:pnObject];
    id minNationalNumberLengthObj = [nationalNumberMinLengths objectForKey:pnObject.countryCode];
    NSUInteger minNationalNumberLength = minNationalNumberLengthObj ? [minNationalNumberLengthObj unsignedIntegerValue] : 0;
    if ([nationalNumber length] < minNationalNumberLength) {
        return nil;
    }

    NSError *formatError = nil;
    NSString *parsed = [phoneNumberUtil format:pnObject
                                  numberFormat:NBEPhoneNumberFormatE164
                                         error:&formatError];
    if (formatError) {
        MAVEDebugLog(@"Error %@ formatting phone number %@", formatError, phoneNumber);
        return nil;
    }
    return parsed;
}

+ (BOOL)looksLikeEmail:(NSString *)email {
    NSString *pattern = @"\\S+@\\S+";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray *matches = [regex matchesInString:email options:0 range:NSMakeRange(0, [email length])];
    return [matches count] != 0;
}


// For now, phone is required so this will always return exactly one phone
// number that we should send the invite to
- (NSString *)bestPhone {
    NSString *val = nil;
    unsigned long numPhones = [self.phoneNumbers count];
    int i;
    // Check for mobile
    for (i=0; i < numPhones; i++) {
        if ([self.phoneNumberLabels[i] isEqual:@"_$!<Mobile>!$_"]) {
            val = self.phoneNumbers[i];
            break;
        }
    }
    // If not found check for Main
    if (val == nil) {
        for (i=0; i < numPhones; i++) {
            if ([self.phoneNumberLabels[i] isEqual:@"_$!<Main>!$_"]) {
                val = self.phoneNumbers[i];
                break;
            }
        }
    }
    // Otherwise use the first one
    if (val == nil && numPhones > 0) {
        val = self.phoneNumbers[0];
    }
    return val;
}

// Phone number here should already have been parsed so it should be in E.164 format
//
// To display it, we use the "National" format (has no country code) if the number is
// in the same country as the device's current setting, otherwise we use the
// "International" format which does have the country code.
// Finally, we also replace any plain spaces with non line breaking spaces, which is
// what e.g. iOS uses when it formats a number as you type it in.
+ (NSString *)displayPhoneNumber:(NSString *)phoneNumber {
    NBPhoneNumberUtil *phoneNumberUtil = [[NBPhoneNumberUtil alloc] init];
    NBPhoneNumber *pnObject = [phoneNumberUtil parseWithPhoneCarrierRegion:phoneNumber error:nil];
    NSString *isoCountryCode = [phoneNumberUtil getRegionCodeForCountryCode:pnObject.countryCode];
    NBEPhoneNumberFormat formatAs;
    if ([isoCountryCode isEqualToString:[MAVEClientPropertyUtils countryCode]]) {
        formatAs = NBEPhoneNumberFormatNATIONAL;
    } else {
        formatAs = NBEPhoneNumberFormatINTERNATIONAL;
    }
    // change regular spaces to non line breaking whitespace (that's what iOS uses when it
    // formats a number as you type it in)
    NSError *formatError = nil;
    NSString *stringWithNormalSpaces = [phoneNumberUtil format:pnObject
                                                  numberFormat:formatAs
                                                         error:&formatError];
    if (formatError) {
        return phoneNumber;
    }
    return [stringWithNormalSpaces stringByReplacingOccurrencesOfString:@" " withString:@"\u00a0"];
}

- (NSComparisonResult)compareNames:(MAVEABPerson *)otherPerson {
    return [[self nameForCompareNames] compare:[otherPerson nameForCompareNames]];
}

- (NSString *)nameForCompareNames {
    NSString * fn = self.firstName;
    if (fn == nil) fn = @"";
    NSString *ln = self.lastName;
    if (ln == nil) ln = @"";
    return [NSString stringWithFormat:@"%@%@",fn,ln];
}

- (NSComparisonResult)compareRecordIDs:(MAVEABPerson *)otherPerson {
    if (self.recordID > otherPerson.recordID) {
        return NSOrderedDescending;
    } else if (self.recordID == otherPerson.recordID) {
        return NSOrderedSame;
    } else {
        return NSOrderedAscending;
    }
}

- (NSComparisonResult)compareHashedRecordIDs:(MAVEABPerson *)otherPerson {
    if (self.hashedRecordID > otherPerson.hashedRecordID) {
        return NSOrderedDescending;
    } else if (self.hashedRecordID == otherPerson.hashedRecordID) {
        return NSOrderedSame;
    } else {
        return NSOrderedAscending;
    }
}

@end
