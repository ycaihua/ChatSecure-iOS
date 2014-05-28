//
//  OTRSubscriptionRequestsViewController.m
//  Off the Record
//
//  Created by David on 3/5/13.
//  Copyright (c) 2013 Chris Ballinger. All rights reserved.
//

#import "OTRSubscriptionRequestsViewController.h"
#import "OTRXMPPPresenceSubscriptionRequest.h"
#import "OTRXMPPAccount.h"
#import "OTRDatabaseManager.h"
#import "OTRDatabaseView.h"
#import "Strings.h"
#import "OTRXMPPManager.h"
#import "OTRProtocolManager.h"

#import "YapDatabaseViewMappings.h"
#import "UIActionSheet+Blocks.h"

@interface OTRSubscriptionRequestsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) YapDatabaseConnection *databaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *mappings;

@property (nonatomic, strong) UITableView *tableView;


@end

@implementation OTRSubscriptionRequestsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = SUBSCRIPTION_REQUEST_TITLE;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonPressed:)];
    
    
    ////// Setup UITableView //////
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[tableView]|" options:0 metrics:0 views:@{@"tableView":self.tableView}]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[tableView]|" options:0 metrics:0 views:@{@"tableView":self.tableView}]];
    
    
    ////// Setup Connection //////
    self.databaseConnection = [OTRDatabaseManager sharedInstance].mainThreadReadOnlyDatabaseConnection;
    
    self.mappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[OTRAllPresenceSubscriptionRequestGroup]
                                                               view:OTRAllSubscriptionRequestsViewExtensionName];
    
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.mappings updateWithTransaction:transaction];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:OTRUIDatabaseConnectionDidUpdateNotification
                                               object:nil];
    
}

-(void)doneButtonPressed:(id)sender
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (OTRXMPPPresenceSubscriptionRequest *)subscriptionRequestAtIndexPath:(NSIndexPath *)indexPath
{
    __block OTRXMPPPresenceSubscriptionRequest *request = nil;
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        request = [[transaction extension:OTRAllSubscriptionRequestsViewExtensionName] objectAtIndexPath:indexPath withMappings:self.mappings];
    }];
    return request;
}

- (OTRXMPPAccount *)accountAtIndexPath:(NSIndexPath *)indexPath
{
    __block OTRXMPPAccount *account = nil;
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        OTRXMPPPresenceSubscriptionRequest *request = [[transaction extension:OTRAllSubscriptionRequestsViewExtensionName] objectAtIndexPath:indexPath withMappings:self.mappings];
        account = [request accountWithTransaction:transaction];
    }];
    return account;
}

- (OTRXMPPManager *)managerAtIndexPath:(NSIndexPath *)indexPath
{
    OTRXMPPAccount *account = [self accountAtIndexPath:indexPath];
    return (OTRXMPPManager *)[[OTRProtocolManager sharedInstance] protocolForAccount:account];
}

- (void)deleteSubscriptionRequest:(OTRXMPPPresenceSubscriptionRequest *)subscriptionRequest
{
    [[OTRDatabaseManager sharedInstance].readWriteDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:nil forKey:subscriptionRequest.uniqueId inCollection:[OTRXMPPPresenceSubscriptionRequest collection]];
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.mappings numberOfSections];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.mappings numberOfItemsInSection:section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    OTRXMPPPresenceSubscriptionRequest * subRequest = [self subscriptionRequestAtIndexPath:indexPath];
    OTRXMPPAccount *account = [self accountAtIndexPath:indexPath];
    OTRXMPPManager *manager = [self managerAtIndexPath:indexPath];
    
    cell.textLabel.text = subRequest.jid;
    cell.detailTextLabel.text = account.username;
    
    if (manager.connectionStatus == OTRProtocolConnectionStatusConnected) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OTRXMPPPresenceSubscriptionRequest *request = [self subscriptionRequestAtIndexPath:indexPath];
    OTRXMPPManager * manager = [self managerAtIndexPath:indexPath];
    XMPPJID *jid = [XMPPJID jidWithString:request.jid];
    
    if (manager.connectionStatus == OTRProtocolConnectionStatusConnected) {
        RIButtonItem *cancelButton = [RIButtonItem itemWithLabel:CANCEL_STRING];
        RIButtonItem *rejectButton = [RIButtonItem itemWithLabel:REJECT_STRING action:^{
            [manager.xmppRoster rejectPresenceSubscriptionRequestFrom:jid];
            [self deleteSubscriptionRequest:request];
        }];
        RIButtonItem *addButton = [RIButtonItem itemWithLabel:ADD_STRING action:^{
            [manager.xmppRoster acceptPresenceSubscriptionRequestFrom:jid andAddToRoster:YES];
            [self deleteSubscriptionRequest:request];
        }];
        UIActionSheet *actionSeet = [[UIActionSheet alloc] initWithTitle:request.jid cancelButtonItem:cancelButton destructiveButtonItem:rejectButton otherButtonItems:addButton, nil];
        
        [actionSeet showInView:self.view];
    }
    
    
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma - mark YapDatabase Methods

- (void)yapDatabaseModified:(NSNotification *)notification
{
    // Process the notification(s),
    // and get the change-set(s) as applies to my view and mappings configuration.
    NSArray *notifications = notification.userInfo[@"notifications"];
    
    NSArray *sectionChanges = nil;
    NSArray *rowChanges = nil;
    
    [[self.databaseConnection ext:OTRAllSubscriptionRequestsViewExtensionName] getSectionChanges:&sectionChanges
                                                                                   rowChanges:&rowChanges
                                                                             forNotifications:notifications
                                                                                 withMappings:self.mappings];
    
    // No need to update mappings.
    // The above method did it automatically.
    
    if ([sectionChanges count] == 0 & [rowChanges count] == 0)
    {
        // Nothing has changed that affects our tableView
        return;
    }
    
    // Familiar with NSFetchedResultsController?
    // Then this should look pretty familiar
    
    [self.tableView beginUpdates];
    
    for (YapDatabaseViewSectionChange *sectionChange in sectionChanges)
    {
        switch (sectionChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionChange.index]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate:
            case YapDatabaseViewChangeMove:
                break;
        }
    }
    
    for (YapDatabaseViewRowChange *rowChange in rowChanges)
    {
        switch (rowChange.type)
        {
            case YapDatabaseViewChangeDelete :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeInsert :
            {
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeMove :
            {
                [self.tableView deleteRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[ rowChange.newIndexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                break;
            }
            case YapDatabaseViewChangeUpdate :
            {
                [self.tableView reloadRowsAtIndexPaths:@[ rowChange.indexPath ]
                                      withRowAnimation:UITableViewRowAnimationNone];
                break;
            }
        }
    }
    
    [self.tableView endUpdates];
}

@end
