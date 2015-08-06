//
//  MAVEContactsInvitePageDataManager.m
//  MaveSDK
//
//  Created by Danny Cosson on 5/22/15.
//
//

#import "MAVEContactsInvitePageDataManager.h"
#import "MaveSDK.h"
#import "MAVEABUtils.h"

// Use arbitrary non-letter code points, in our sorting function we'll
// explicitly set the suggestions first and non-alphabet chars last
NSString * const MAVESuggestedInvitesTableDataKey = @"\u2605";
NSString * const MAVENonAlphabetNamesTableDataKey = @"#";

@implementation MAVEContactsInvitePageDataManager

- (instancetype)init {
    if (self = [super init]) {
        [self doInitialSetup];
    }
    return self;
}

- (void)doInitialSetup {
}

- (NSArray *)sectionIndexesForMainTable {
    return self.mainTableSectionKeys;
}
- (NSInteger)numberOfSectionsInMainTable {
    return [[self sectionIndexesForMainTable] count];
}
- (NSInteger)numberOfRowsInMainTableSection:(NSUInteger)section {
    NSString *sectionKey = [[self sectionIndexesForMainTable] objectAtIndex:section];
    NSArray *rows = [self.mainTableData objectForKey:sectionKey];
    return [rows count];
}

- (MAVEABPerson *)personAtMainTableIndexPath:(NSIndexPath *)indexPath {
    NSString *sectionKey = [[self sectionIndexesForMainTable] objectAtIndex:indexPath.section];
    NSArray *rows = [self.mainTableData objectForKey:sectionKey];
    return [rows objectAtIndex:indexPath.row];
}

- (NSIndexPath *)indexPathOfFirstOccuranceInMainTableOfPerson:(MAVEABPerson *)person {
    NSNumber *personKey = [NSNumber numberWithInteger:person.recordID];
    return [[self.personToIndexPathsIndex objectForKey:personKey] objectAtIndex:0];
}

- (MAVEABPerson *)personAtSearchTableIndexPath:(NSIndexPath *)indexPath {
    if (![self.searchTableData count] - 1 >= indexPath.row) {
        return nil;
    }
    return [self.searchTableData objectAtIndex:indexPath.row];
}

- (void)setMainTableData:(NSDictionary *)mainTableData {
    _mainTableData = mainTableData;
    self.mainTableSectionKeys = [[self class] sortedSectionKeys:[mainTableData allKeys]];
    [self updateMainTablePersonToIndexPathsIndex];
    self.allContacts = [self enumerateAllContacts];
}

+ (NSArray *)sortedSectionKeys:(NSArray *)sectionKeys {
    return [sectionKeys sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSString *s1 = obj1, *s2 = obj2;
        if ([s1 isEqualToString:MAVESuggestedInvitesTableDataKey]) {
            return NSOrderedAscending;
        }
        if ([s2 isEqualToString:MAVESuggestedInvitesTableDataKey]) {
            return NSOrderedDescending;
        }
        if ([s1 isEqualToString:MAVENonAlphabetNamesTableDataKey]) {
            return NSOrderedDescending;
        }
        if ([s2 isEqualToString:MAVENonAlphabetNamesTableDataKey]) {
            return NSOrderedAscending;
        }
        return [s1 localizedCaseInsensitiveCompare:s2];
    }];
}

- (NSArray *)enumerateAllContacts {
    NSMutableArray *mutableAllPeople = [NSMutableArray array];
    NSMutableSet *mutableAllPeopleUnique = [[NSMutableSet alloc] init];
    for (NSString *sectionKey in self.mainTableSectionKeys) {
        NSArray *section = [self.mainTableData objectForKey:sectionKey];
        for (MAVEABPerson *person in section) {
            if (![mutableAllPeopleUnique containsObject:person]) {
                [mutableAllPeople addObject:person];
                [mutableAllPeopleUnique addObject:person];
            }
        }
    }
    return [NSArray arrayWithArray:mutableAllPeople];}

- (void)updateMainTablePersonToIndexPathsIndex {
    NSNumber *personKey;
    NSIndexPath *idxPath; NSInteger sectionIdx = 0, rowIdx = 0;
    NSMutableDictionary *index = [[NSMutableDictionary alloc] init];
    for (NSString *sectionKey in [self sectionIndexesForMainTable]) {
        rowIdx = 0;
        for (MAVEABPerson *person in [self.mainTableData objectForKey:sectionKey]) {
            personKey = [NSNumber numberWithInteger:person.recordID];
            idxPath = [NSIndexPath indexPathForRow:rowIdx inSection:sectionIdx];
            if (![index objectForKey:personKey]) {
                [index setObject:[[NSMutableArray alloc] init] forKey:personKey];
            }
            [[index objectForKey:personKey] addObject:idxPath];
            rowIdx++;
        }
        sectionIdx++;
    }
    self.personToIndexPathsIndex = index;
}

- (void)updateWithContacts:(NSArray *)contacts ifNecessaryAsyncSuggestionsBlock:(void (^)(NSArray *))asyncSuggestionsBlock noSuggestionsToAddBlock:(void (^)())noSuggestionsBlock {
    NSDictionary *indexedContactsToRenderNow;
    BOOL updateSuggestionsWhenReady = NO;
    [[self class] buildContactsToUseAtPageRender:&indexedContactsToRenderNow
                      addSuggestedLaterWhenReady:&updateSuggestionsWhenReady
                                fromContactsList:contacts];
    self.mainTableData = indexedContactsToRenderNow;
    
    if (updateSuggestionsWhenReady && asyncSuggestionsBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            NSArray *suggestions = [[MaveSDK sharedInstance] suggestedInvitesWithFullContactsList:contacts delay:10];
            dispatch_async(dispatch_get_main_queue(), ^{
                asyncSuggestionsBlock(suggestions);
            });
        });
    }
    if (!updateSuggestionsWhenReady && noSuggestionsBlock) {
        noSuggestionsBlock();
    }
}

+ (void)buildContactsToUseAtPageRender:(NSDictionary **)suggestedContactsReturnVal
            addSuggestedLaterWhenReady:(BOOL *)addSuggestedLaterReturnVal
                      fromContactsList:(NSArray *)contacts {
    BOOL suggestionsEnabled = [MaveSDK sharedInstance].remoteConfiguration.contactsInvitePage.suggestedInvitesEnabled;
    if (!suggestionsEnabled) {
        *suggestedContactsReturnVal = [MAVEABUtils indexABPersonArrayForTableSections:contacts];
        *addSuggestedLaterReturnVal = NO;
        return;
    }
    BOOL suggestionsReady = [MaveSDK sharedInstance].suggestedInvitesBuilder.promise.status != MAVEPromiseStatusUnfulfilled;
    if (!suggestionsReady) {
        NSDictionary *indexedContacts = [MAVEABUtils indexABPersonArrayForTableSections:contacts];
        *suggestedContactsReturnVal = [MAVEABUtils combineSuggested:@[] intoABIndexedForTableSections:indexedContacts];
        *addSuggestedLaterReturnVal = YES;
        return;
    }

    NSArray *suggestions = [[MaveSDK sharedInstance] suggestedInvitesWithFullContactsList:contacts delay:0];
    NSDictionary *indexedContacts = [MAVEABUtils indexABPersonArrayForTableSections:contacts];
    if ([suggestions count] > 0) {
        *suggestedContactsReturnVal = [MAVEABUtils combineSuggested:suggestions intoABIndexedForTableSections:indexedContacts];
    } else {
        *suggestedContactsReturnVal = indexedContacts;
    }
    *addSuggestedLaterReturnVal = NO;
}



@end
