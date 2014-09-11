//
//  OBViewController.m
//  FileTransferPlay
//
//  Created by Farhad Farzaneh on 6/20/14.
//  Copyright (c) 2014 OneBeat. All rights reserved.
//

#import "OBViewController.h"
#import <OBLogger/OBLogger.h>
#import "OBTransferView.h"

@interface OBViewController ()
@property (nonatomic) NSMutableDictionary * transferViews;
@property (nonatomic) OBFileTransferManager * fileTransferManager;
@property (nonatomic) BOOL useS3;
@property (nonatomic,strong) NSString * baseUrl;
@end

@implementation OBViewController

// --------------
// Lazy instantiations
// --------------
-(NSMutableDictionary *) transferViews
{
    if ( _transferViews == nil )
        _transferViews =  [NSMutableDictionary new];
    return _transferViews;
}

-(OBFileTransferManager *) fileTransferManager
{
    if ( _fileTransferManager == nil ) {
        _fileTransferManager =[OBFileTransferManager instance];
        _fileTransferManager.delegate = self;
        _fileTransferManager.downloadDirectory = [self documentDirectory];
        
        _fileTransferManager.remoteUrlBase = self.baseUrl;
//        _fileTransferManager.maxAttempts = 2;
        
//        _fileTransferManager.remoteUrlBase = @"http://localhost:3000/api/upload/";
//        _fileTransferManager.remoteUrlBase = @"http://localhost:3000/videos/create";
    }
    return _fileTransferManager;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setup];
    OB_INFO(@"START");
}

-(void) setup
{
    self.useS3 = YES;
    self.useS3Switch.on = self.useS3;
    [self setDefaultURLs];
    [self displayPending];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UI Actions

//NOTE: these are files that we know are there!
-(IBAction)start:(id)sender
{
    [self clearTransferViews];
    [self.fileTransferManager reset:^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
            [self displayPending];
            [self uploadFile: @"uploadtest.jpg"];
            [self downloadFile:@"testdownload1.jpg"];
            [self downloadFile:@"testdownload2.jpg"];
            [self uploadFile: @"uploadtest.jpg"];
            [self downloadFile:@"test9062_nothere.jpg"];
        }];
    }];
}

-(IBAction)retryPending:(id)sender
{
    [self clearTransferViews];
    for ( NSDictionary * taskInfo in [self.fileTransferManager currentState] ) {
        NSString * filename;
        if ( [taskInfo[OBFTMTypeUploadKey] boolValue] ) {
             filename = taskInfo[OBFTMParamsKey][FilenameParamKey];
        } else
            filename = [taskInfo[OBFTMLocalFilePathKey] lastPathComponent];
        
        [self addTransferView: filename isUpload:[taskInfo[OBFTMTypeUploadKey] boolValue]];
    }
    [self.fileTransferManager retryPending];
    [self displayPending];
}

// Change the file store and appropriate URL
- (IBAction)changedFileStore:(id)sender {
    self.useS3 = self.useS3Switch.on;
    [self setDefaultURLs];
    self.fileTransferManager.remoteUrlBase = self.baseUrl;
}

- (IBAction)changedFileStoreUrl:(id)sender {
    self.baseUrl = self.baseUrlInput.text;
    self.fileTransferManager.remoteUrlBase = self.baseUrl;
}


#pragma mark - FileTransferDelegate Protocol

-(void)fileTransferCompleted:(NSString *)markerId withError:(NSError *)error
{
    OB_INFO(@"Completed file transfer with marker %@ and error %@",markerId,error.localizedDescription);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(OBTransferView *)self.transferViews[markerId] updateStatus:error == nil ? Success : Error];
        [self displayPending];
    }];
    
}

-(void)fileTransferRetrying:(NSString *)markerId attemptCount: (NSUInteger)attemptCount withError:(NSError *)error
{
    OB_INFO(@"File transfer with marker %@ pending retry",markerId);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(OBTransferView *)self.transferViews[markerId] updateProgress:0.0];
        [(OBTransferView *)self.transferViews[markerId] updateStatus:PendingRetry retryCount:attemptCount-1];
        [self displayPending];
    }];
}

-(void) fileTransferProgress: (NSString *)markerId progress:(OBTransferProgress)progress
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^ {
        [(OBTransferView *)self.transferViews[markerId] updateProgress:progress.percentDone];
    }];
}

//-(NSTimeInterval) retryTimeoutValue:(NSInteger)retryAttempt
//{
//    return (NSTimeInterval) 3;
//}
//
#pragma mark - Utility

-(void) displayPending
{
    self.pendingInfo.text = [self.fileTransferManager pendingSummary];
}

-(void) uploadFile: (NSString *)filename
{
    NSString * uploadBase =@"";
    if ( !self.useS3 )
        uploadBase = @"upload/";
    
    NSString * localFilePath = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
    NSString *targetFilename = [NSString stringWithFormat:@"test%d.jpg", arc4random_uniform(10000)];
    [self.fileTransferManager uploadFile:localFilePath to:uploadBase withMarker:targetFilename withParams:@{FilenameParamKey: targetFilename, @"p1":@"test"}];
    [self addTransferView:targetFilename isUpload:YES];
    
}

-(void) downloadFile: (NSString *)filename
{
    static NSString * base=@"";
    if ( !self.useS3 )
        base = @"files/";
    
    [self.fileTransferManager downloadFile:[base  stringByAppendingString:filename] to:filename withMarker:filename withParams:nil];
    [self addTransferView:filename isUpload:NO];
}


-(void) addTransferView: (NSString *) fileName isUpload: (BOOL) isUpload
{
    OBTransferView *transferView = [[OBTransferView alloc] initInRow: self.transferViews.count];
    [transferView startTransfer:fileName upload:isUpload ? Upload : Download];
    [self.transferViewArea addSubview:transferView];
    self.transferViews[fileName] = transferView;
}

-(void) clearTransferViews
{
    for ( UIView * view in self.transferViewArea.subviews )
        [view removeFromSuperview];
    [self.transferViews removeAllObjects];
}

-(void) setDefaultURLs
{
    if ( self.useS3 )
        self.baseUrl = @"s3://tbm_videos/";
    else
        self.baseUrl = @"http://192.168.1.9:3000/";
    self.baseUrlInput.text = self.baseUrl;
}

// Put files in document directory
-(NSString *) documentDirectory
{
    NSArray * urls = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                            inDomains:NSUserDomainMask];
    if ( urls.count > 0 ) {
        return [(NSURL *)urls[0] URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]].path;
    } else
        return nil;
}


- (IBAction)reset:(id)sender {
    [self.fileTransferManager reset: ^{
        [self displayPending];
        [self clearTransferViews];
    }];
}

- (IBAction)showLog:(id)sender {
    OBLogViewController *logViewer = [OBLogViewController instance];
    [self presentViewController:logViewer animated:YES completion:nil];
}

- (IBAction)restart:(id)sender {
    [[self fileTransferManager] restartAllTasks:^{
        OB_INFO(@"Finished restarting the tasks");
    }];
}

@end
