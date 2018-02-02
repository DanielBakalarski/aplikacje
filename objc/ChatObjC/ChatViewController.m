//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "Constants.h"
#import "ChatViewController.h"

@import Firebase;
@import GoogleMobileAds;
@import Crashlytics;

@interface ChatViewController ()<UITableViewDataSource, UITableViewDelegate,
UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, FIRInviteDelegate> {
  int _msglength;
  FIRDatabaseHandle _refHandle;
}

@property(nonatomic, strong) IBOutlet UITextField *textField;
@property(nonatomic, strong) IBOutlet UIButton *sendButton;

@property(nonatomic, weak) IBOutlet UITableView *clientTable;

@property (strong, nonatomic) FIRDatabaseReference *ref;
@property (strong, nonatomic) NSMutableArray<FIRDataSnapshot *> *messages;
@property (strong, nonatomic) FIRStorageReference *storageRef;
@property (nonatomic, strong) FIRRemoteConfig *remoteConfig;

@end

@implementation ChatViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  _msglength = 20;
  _messages = [[NSMutableArray alloc] init];
  [_clientTable registerClass:UITableViewCell.self forCellReuseIdentifier:@"tableViewCell"];

  [self configureDatabase];
  [self configureStorage];
  [self configureRemoteConfig];
  [self fetchConfig];
}

-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
}

- (void)dealloc {
  [[_ref child:@"messages"] removeObserverWithHandle:_refHandle];
}

- (void)configureDatabase {
  _ref = [[FIRDatabase database] reference];
  _refHandle = [[_ref child:@"messages"] observeEventType:FIRDataEventTypeChildAdded withBlock:^(FIRDataSnapshot *snapshot) {
    [_messages addObject:snapshot];
    [_clientTable insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:_messages.count-1 inSection:0]] withRowAnimation: UITableViewRowAnimationAutomatic];
  }];
}

- (void)configureStorage {
  _storageRef = [[FIRStorage storage] reference];
}

- (void)configureRemoteConfig {
  _remoteConfig = [FIRRemoteConfig remoteConfig];
  FIRRemoteConfigSettings *remoteConfigSettings = [[FIRRemoteConfigSettings alloc] initWithDeveloperModeEnabled:YES];
  _remoteConfig.configSettings = remoteConfigSettings;
}

- (void)fetchConfig {
  long expirationDuration = 3600;
  // If in developer mode cacheExpiration is set to 0 so each fetch will retrieve values from
  // the server.
  if (_remoteConfig.configSettings.isDeveloperModeEnabled) {
    expirationDuration = 0;
  }
  [_remoteConfig fetchWithExpirationDuration:expirationDuration completionHandler:^(FIRRemoteConfigFetchStatus status, NSError *error) {
    if (status == FIRRemoteConfigFetchStatusSuccess) {
      NSLog(@"Config fetched!");
      [_remoteConfig activateFetched];
      FIRRemoteConfigValue *friendlyMsgLength = _remoteConfig[@"friendly_msg_length"];
      if (friendlyMsgLength.source != FIRRemoteConfigSourceStatic) {
        _msglength = friendlyMsgLength.numberValue.intValue;
        NSLog(@"Friendly msg length config: %d", _msglength);
      }
    } else {
      NSLog(@"Config not fetched");
      NSLog(@"Error %@", error);
    }
  }];
}


- (IBAction)didSendMessage:(UIButton *)sender {
  [self sendText:_textField];
}

// UITableViewDataSource protocol methods
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return _messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
  // Dequeue cell
  UITableViewCell *cell = [_clientTable dequeueReusableCellWithIdentifier:@"tableViewCell" forIndexPath:indexPath];

  // Unpack message from Firebase DataSnapshot
  FIRDataSnapshot *messageSnapshot = _messages[indexPath.row];
  NSDictionary<NSString *, NSString *> *message = messageSnapshot.value;
  NSString *name = message[MessageFieldsname];
  NSString *imageURL = message[MessageFieldsimageURL];
  if (imageURL) {
    if ([imageURL hasPrefix:@"gs://"]) {
      [[[FIRStorage storage] referenceForURL:imageURL] dataWithMaxSize:INT64_MAX
                                                            completion:^(NSData *data, NSError *error) {
        if (error) {
          NSLog(@"Error downloading: %@", error);
          return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
          cell.imageView.image = [UIImage imageWithData:data];
          [cell setNeedsLayout];
        });
      }];
    } else {
      cell.imageView.image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageURL]]];
    }
    cell.textLabel.text = [NSString stringWithFormat:@"sent by: %@", name];
  } else {
    NSString *text = message[MessageFieldstext];
    cell.textLabel.text = [NSString stringWithFormat:@"%@: %@", name, text];
    cell.imageView.image = [UIImage imageNamed: @"ic_account_circle"];
    NSString *photoURL = message[MessageFieldsphotoURL];
    if (photoURL) {
      NSURL *URL = [NSURL URLWithString:photoURL];
      if (URL) {
        NSData *data = [NSData dataWithContentsOfURL:URL];
        if (data) {
          cell.imageView.image = [UIImage imageWithData:data];
        }
      }
    }
  }
  return cell;
}

- (void)sendText:(UITextField *)textField {
  [self sendMessage:@{MessageFieldstext: textField.text}];
  textField.text = @"";
  [self.view endEditing:YES];
}

- (void)sendMessage:(NSDictionary *)data {
  NSMutableDictionary *mdata = [data mutableCopy];
  mdata[MessageFieldsname] = [FIRAuth auth].currentUser.displayName;
  NSURL *photoURL = [FIRAuth auth].currentUser.photoURL;
  if (photoURL) {
    mdata[MessageFieldsphotoURL] = photoURL.absoluteString;
  }

  // Push data to Firebase Database
  [[[_ref child:@"messages"] childByAutoId] setValue:mdata];
}


-(void)textFieldDidBeginEditing:(UITextField *)textField {
    //Keyboard becomes visible
    _textFieldConstraint.constant = 340;
    _sendButtonConstraint.constant = 340;
}

-(void)textFieldDidEndEditing:(UITextField *)textField {
    //keyboard will hide
    _textFieldConstraint.constant = 30;
    _sendButtonConstraint.constant = 30;
}

- (IBAction)signOut:(UIButton *)sender {
  FIRAuth *firebaseAuth = [FIRAuth auth];
  NSError *signOutError;
  BOOL status = [firebaseAuth signOut:&signOutError];
  if (!status) {
    NSLog(@"Error signing out: %@", signOutError);
    return;
  }
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleDestructive handler:nil];
    [alert addAction:dismissAction];
    [self presentViewController:alert animated: true completion: nil];
  });
}

@end
