//
//  ViewController.m
//  LargeFileDownload
//
//  Created by guoliting on 2019/10/18.
//  Copyright © 2019 guoliting. All rights reserved.
//

#import "ViewController.h"

// 下载状态
typedef enum DownloadStatus{
    DOWNLOAD_STATUS_NOT_STARTED = 0, //未开始
    DOWNLOAD_STATUS_STARTED, //正在下载
    DOWNLOAD_STATUS_SUSPEND //暂停
}DownloadStatus;

static NSString *resumeDataFile = @"resumeDataFile.tmp";
static NSString *downloadProgressKey = @"downloadProgress"; //下载进度Key值

@interface ViewController () <NSURLSessionDelegate>

@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UITextField *progressTextField; //下载进度
@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask; //下载任务
@property(nonatomic) NSUInteger downloadStatus; //下载状态
@property (nonatomic, strong) NSData *resumeData; //应用异常退出时下载文件缓存
@property(nonatomic) NSUInteger downloadProgress; //下载进度

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    int offset = 20;
    
    //下载
    CGFloat originX = 50;
    CGFloat originY = 100;
    CGFloat buttonWidth = 150;
    CGFloat buttonHeight = 30;
    _downloadButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _downloadButton.frame = CGRectMake(originX, originY, buttonWidth / 2, buttonHeight);
    _downloadButton.backgroundColor = [UIColor greenColor];
    [_downloadButton.titleLabel setFont:[UIFont systemFontOfSize:20]];
    [_downloadButton setTitleColor:[UIColor redColor] forState:UIControlStateHighlighted];
    [_downloadButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [_downloadButton addTarget:self action:@selector(downloadFile) forControlEvents:UIControlEventTouchUpInside];
//    [[_downloadButton layer] setBorderColor:[[UIColor blueColor] CGColor]];
    [[_downloadButton layer] setBorderWidth:1];
    [self.view addSubview:_downloadButton];
    
    _resumeData = [NSData dataWithContentsOfFile:[[self finallyFilePath] stringByAppendingPathComponent:resumeDataFile] options:NSDataReadingMappedIfSafe error:nil];
    _downloadProgress = 0;
    if (_resumeData) {
        [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_SUSPEND];
        
        id object = [[NSUserDefaults standardUserDefaults] objectForKey:downloadProgressKey];
        if (object) {
            _downloadProgress = [object unsignedIntegerValue];
        }
    } else {
        [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_NOT_STARTED];
    }
    
    originX += buttonWidth + offset;
    _progressTextField = [[UITextField alloc] initWithFrame:(CGRect){originX, originY, buttonWidth / 2, buttonHeight}];
    [_progressTextField setBackgroundColor:[UIColor greenColor]];
    _progressTextField.text = [NSString stringWithFormat:@"%lu%%", (unsigned long)_downloadProgress];
    [self.view addSubview:_progressTextField];
    
    //监听应用被终止时的通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
    //监听应用进入后台时的通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    //监听应用进入前台时的通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    
    // 自动隐藏键盘
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(dismissKeyboard)];
    
    [self.view addGestureRecognizer:tap];
}

- (void)changeDownloadButtonTitleByStatus:(DownloadStatus)status {
    __weak typeof(self) weakSelf = self; //避免block循环引用
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.downloadStatus = status;
        NSString *title = @"下载";
        if (DOWNLOAD_STATUS_SUSPEND == status) {
            title = @"继续";
        } else if (DOWNLOAD_STATUS_STARTED == status) {
            title = @"暂停";
        }
        [strongSelf.downloadButton setTitle:title forState:UIControlStateNormal];
    });
}

- (void)saveResumeData {
    if (_downloadTask) {
        __weak typeof(self) weakSelf = self; //避免block循环引用
        [_downloadTask cancelByProducingResumeData:^(NSData *resumeData) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            NSString *filePath = [[self finallyFilePath] stringByAppendingPathComponent:resumeDataFile];
            if(resumeData) {
                strongSelf.resumeData = resumeData;
                [resumeData writeToFile:filePath atomically:YES];
            } else {
                [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
            }
            
            if (DOWNLOAD_STATUS_STARTED == strongSelf.downloadStatus) {
                // 进入主线程刷新UI
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (strongSelf.downloadProgress < 100 && strongSelf.downloadProgress > 0) {
                        //进入后台时，暂停下载
                        [self suspendDownloadFile];
                    }
                });
            }
            
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithUnsignedInteger:strongSelf.downloadProgress] forKey:downloadProgressKey];
        }];
    }
}

- (void)appWillTerminate {
    NSLog(@"appWillTerminate");
    [self saveResumeData];
}

- (void)appWillResignActive {
    NSLog(@"appWillResignActive");
    [self saveResumeData];
}

- (void)appWillEnterForeground {
    NSLog(@"appWillEnterForeground");
    [self resumeDownloadFile];
}

- (void)suspendDownloadFile {
    if (_downloadTask) {
        [_downloadTask suspend];
        [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_SUSPEND];
        //        [_datFiles addObject:nil];
    }
}

- (void)resumeDownloadFile {
    if (_resumeData) {
        [self downloadFileByRequest:nil];
    } else {
        if (_downloadTask) {
            [_downloadTask resume];
        }
    }
    
    [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_STARTED];
}

- (NSString *)finallyFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *tmp = [paths lastObject];
    NSString *filePath = [tmp stringByAppendingPathComponent:@"download"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:filePath withIntermediateDirectories:NO attributes:nil error:nil]) {
            return @"";
        }
    }
    
    return filePath;
}

//- (NSString *)resumeDataFilePath {
//    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
//    NSString *tmp = [paths lastObject];
//    NSString *filePath = [tmp stringByAppendingPathComponent:@"resumeData"];
//
//    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
//        if (![[NSFileManager defaultManager] createDirectoryAtPath:filePath withIntermediateDirectories:NO attributes:nil error:nil]) {
//            return @"";
//        }
//    }
//
//    return [filePath stringByAppendingPathComponent:resumeDataFile];
//}

- (void)downloadFileByRequest:(NSURLRequest *)request {
    //默认配置
    //    [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@""]; //后台session
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    sessionConfiguration.timeoutIntervalForRequest = 60.0; //请求超时时间；默认为60秒
    sessionConfiguration.allowsCellularAccess = YES; //是否允许蜂窝网络访问（2G/3G/4G）
    sessionConfiguration.HTTPMaximumConnectionsPerHost = 4; //限制每次最多连接数；在 iOS 中默认值为4
    //创建会话管理器，依赖AFNetWorking
    //    AFURLSessionManager *sessionManager = [[AFURLSessionManager alloc] initWithSessionConfiguration:sessionConfiguration];
    NSURLSession *currentSession = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:nil];
    
    if (request) {
        _downloadTask = [currentSession downloadTaskWithRequest:request];
        
        //        _downloadTask = [sessionManager downloadTaskWithRequest:request progress:nil destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        //            //当 sessionManager 调用 setDownloadTaskDidFinishDownloadingBlock: 方法，并且方法代码块返回值不为 nil 时（优先级高），下面的两句代码是不执行的（优先级低）
        //            NSLog(@"下载后的临时保存路径：%@", targetPath);
        //
        //            return targetPath;
        //        } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        //            [self completionDownloadWithResponse:response filePath:filePath error:error];
        //        }];
    } else {
        if (_resumeData) {
            _downloadTask = [currentSession downloadTaskWithResumeData:_resumeData];
            
            //            _downloadTask = [sessionManager downloadTaskWithResumeData:_resumeData progress:nil destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
            //                //当 sessionManager 调用 setDownloadTaskDidFinishDownloadingBlock: 方法，并且方法代码块返回值不为 nil 时（优先级高），下面的两句代码是不执行的（优先级低）
            //                NSLog(@"下载后的临时保存路径：%@", targetPath);
            //
            //                return targetPath;
            //            } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
            //                [self completionDownloadWithResponse:response filePath:filePath error:error];
            //            }];
            
            _resumeData = nil;
        }
    }
    
    //类似 NSURLSessionDownloadDelegate 的方法操作
    //- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
    //    [sessionManager setDownloadTaskDidWriteDataBlock:^ (NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite) {
    //        //                if (![NSThread isMainThread]) {
    //        //                    NSLog(@"当前线程：%@", [NSThread currentThread]);
    //        //                }
    //        // 进入主线程刷新UI
    //        dispatch_async(dispatch_get_main_queue(), ^{
    //            //                    if ([NSThread isMainThread]) {
    //            //                        NSLog(@"主线程：%@", [NSThread currentThread]);
    //            //                    }
    //            _downloadProgress = 100 * totalBytesWritten / totalBytesExpectedToWrite;
    //            _progressTextField.text = [NSString stringWithFormat:@"%lu%%", (unsigned long)_downloadProgress];
    //        });
    //        //                NSLog(@"进度%.2f%%", (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite * 100);
    //        //                NSLog(@"已经接收到响应数据，数据长度为%lld字节...", totalBytesWritten);
    //    }];
    
    //- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location;
    //    [sessionManager setDownloadTaskDidFinishDownloadingBlock:^ NSURL*(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location) {
    //        NSLog(@"已经接收完所有响应数据，下载后的临时保存路径：%@", location);
    //        _downloadProgress = 0;
    //        [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_NOT_STARTED];
    //        [self saveResumeData];
    //        return location;
    //    }];
    
    if (_downloadTask) {
        [_downloadTask resume];
    }
}

- (void)completionDownloadWithResponse:(NSURLResponse * _Nonnull)response filePath:(NSURL * _Nullable)filePath error:(NSError * _Nullable)error {
    if (!_resumeData) {
        [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_NOT_STARTED];
    }
    
    if (!error) {
        NSLog(@"下载后的保存路径：%@", filePath); //为上面代码块返回的路径
    } else {
        NSLog(@"下载失败，错误信息：%@", error.localizedDescription);
    }
}

- (void)downloadFile {
    if (DOWNLOAD_STATUS_STARTED == _downloadStatus) {
        //暂停
        [self suspendDownloadFile];
    } else if (DOWNLOAD_STATUS_SUSPEND == _downloadStatus) {
        //继续
        [self resumeDownloadFile];
    } else if (DOWNLOAD_STATUS_NOT_STARTED == _downloadStatus) {
        //下载
//        NSString *fileName = @"onecarlauncher-debug.apk";
        //        NSString *fileName = @"TTSDemo.zip";
//        NSString *filePath = [[self finallyFilePath] stringByAppendingPathComponent:fileName];
        
        //检查文件是否存在
//        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_STARTED];
            
            //确定请求路径
            NSString *URLString = @"http://116.177.243.228/cdn/pcclient/20191014/12/25/iQIYIMedia_005.dmg?dis_dz=CNC-BeiJing&dis_st=36&ali_redirect_domain=offline-aliyuncdncnc.inter.iqiyi.com&ali_redirect_ex_ftag=71c7e5018c60af8f858d1cebacb3cd42f80f9b5a6a1389fa&ali_redirect_ex_tmining_ts=1571387287&ali_redirect_ex_tmining_expire=3600&";
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
            
            [self downloadFileByRequest:request];
//        }
    }
}

//- (void)downloadFileTest {
//    //    NSString *fileName = @"test_asr-ios-sdk_build_10.ipa";
//    NSString *fileName = @"test_VoiceCar_Android_android_Release_build_10.apk";
//    //    NSString *fileName = @"etts_domain_Zhangyishan_2016126.md5";
//    NSBundle *bundle = [NSBundle mainBundle];
//    NSString *filePath = [[bundle bundlePath] stringByAppendingString:[_kFilePath stringByAppendingPathComponent:fileName]];
//    filePath = [@"/Users/guoliting/test/TTSSDKForiOS" stringByAppendingPathComponent:fileName];
//    NSLog(@"download path:%@", filePath);
//    //检查文件是否存在
//    //    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
//    //确定请求路径
//    //        NSString *URLString = [@"https://buildprod.test.com/download/asr-ios-sdk/ios/Release/ios/output/asr-ios-sdk_ios/10/" stringByAppendingString:fileName];
//    NSString *URLString = [@"https://buildprod.test.com/download/VoiceCar/Android/android/Release/android/output/VoiceCar_Android_android/10/" stringByAppendingString:fileName];
//    //        NSString *URLString = [@"http://bdml-speech.teststatic.com/static/speech/" stringByAppendingString:fileName];
//    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
//
//    //断点续传设置Range
//    u_int64_t offset = 196608;
//    //        if ([self.outputStream propertyForKey:NSStreamFileCurrentOffsetKey]) {
//    //            offset = [(NSNumber *)[self.outputStream propertyForKey:NSStreamFileCurrentOffsetKey] unsignedLongLongValue];
//    //        } else {
//    //            offset = [(NSData *)[self.outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey] length];
//    //        }
//
//    NSMutableURLRequest *mutableURLRequest = [request mutableCopy];
//    //        if ([self.response respondsToSelector:@selector(allHeaderFields)] && [[self.response allHeaderFields] valueForKey:@"ETag"]) {
//    //            [mutableURLRequest setValue:[[self.response allHeaderFields] valueForKey:@"ETag"] forHTTPHeaderField:@"If-Range"];
//    //        }
//    [mutableURLRequest setValue:[NSString stringWithFormat:@"bytes=%llu-", offset] forHTTPHeaderField:@"Range"];
//    request = mutableURLRequest;
//
//    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
//    //shouldAppend为YES支持增量下载
//    operation.outputStream = [NSOutputStream outputStreamToFileAtPath:filePath append:YES];
//    __weak typeof(operation) weakOperation = operation;
//    [operation setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
//        //监听文件下载进度
//        NSLog(@"bytesRead:%lu, totalBytesRead:%lld, totalBytesExpectedToRead:%lld, download progress:%f", (unsigned long)bytesRead, totalBytesRead, totalBytesExpectedToRead, 1.0 * totalBytesRead / totalBytesExpectedToRead);
//        //            [weakOperation pause];
//        //            sleep(1);
//        //            [weakOperation resume];
//    }];
//
//    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
//        // Do nothing.
//        NSLog(@"downloading responseObject:%@", responseObject);
//        //            [self downloadFile];
//        //            [self uploadFile];
//    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
//        NSLog(@"download voice fail.url:%@", filePath);
//    }];
//    [[NSOperationQueue mainQueue] addOperation:operation];
//    //    }
//}

//- (void)uploadFile {
//    //AFN3.0+基于封住HTPPSession的句柄
//    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
//    //formData: 专门用于拼接需要上传的数据,在此位置生成一个要上传的数据体
//    NSString *URLString = [@"https://buildprod.test.com/download/asr-ios-sdk/ios/Release/ios/output/asr-ios-sdk_ios/10/" stringByAppendingString:@""];
//    //    NSString *URLString = [@"https://buildprod.test.com/download/VoiceCar/Android/android/Release/android/output/VoiceCar_Android_android/10/" stringByAppendingString:@""];
//    NSDictionary *dict = @{@"username":@"guoliting"};
//    [manager POST:URLString parameters:dict constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
//        NSString *fileName = @"test_asr-ios-sdk_build_10.ipa";
//        //        NSString *fileName = @"test_VoiceCar_Android_android_Release_build_10.apk";
//        NSBundle *bundle = [NSBundle mainBundle];
//        NSString *filePath = [[bundle bundlePath] stringByAppendingString:[_kFilePath stringByAppendingFormat:@"/%@", fileName]];
//        NSLog(@"file path:%@", filePath);
//        NSData *data = [NSData dataWithContentsOfFile:filePath];
//
//        //上传
//        /*
//         此方法参数
//         1. 要上传的[二进制数据]
//         2. 对应网站上[upload.php中]处理文件的[字段"file"]
//         3. 要保存在服务器上的[文件名]
//         4. 上传文件的[mimeType]
//         */
//        if (data) {
//            [formData appendPartWithFileData:data name:@"file" fileName:fileName mimeType:@"audio/asc"];
//        }
//    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
//        NSLog(@"上传成功 %@", responseObject);
//    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
//        NSLog(@"上传失败 %@", error);
//        //        [self uploadFile];
//    }];
//    return;
//
//    //    NSString *fileName = @"test_asr-ios-sdk_build_10.ipa";
//    NSString *fileName = @"test_VoiceCar_Android_android_Release_build_10.apk";
//    NSBundle *bundle = [NSBundle mainBundle];
//    NSString *filePath = [[bundle bundlePath] stringByAppendingString:[_kFilePath stringByAppendingFormat:@"/%@", fileName]];
//    NSLog(@"file path:%@", filePath);
//    //检查文件是否存在
//    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
//        //确定请求路径
//        //        NSString *URLString = [@"https://buildprod.test.com/download/asr-ios-sdk/ios/Release/ios/output/asr-ios-sdk_ios/10/" stringByAppendingString:fileName];
//        NSString *URLString = [@"https://buildprod.test.com/download/VoiceCar/Android/android/Release/android/output/VoiceCar_Android_android/10/" stringByAppendingString:@"test"];
//        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
//        AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
//
//        //shouldAppend为YES支持增量下载
//        operation.inputStream = [NSInputStream inputStreamWithFileAtPath:filePath];
//        [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
//            // Do nothing.
//            NSLog(@"uploading responseObject:%@", responseObject);
//            [self uploadFile];
//        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
//            NSLog(@"upload voice fail.url:%@", filePath);
//        }];
//        [[NSOperationQueue mainQueue] addOperation:operation];
//    }
//}

#pragma mark - NSURLSessionDelegate
// bytesWritten ：本次写入的数据大小  totalBytesWritten：写入的总大小
// totalBytesExpectedToWrite ：需要下载的数据的总大小
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    //监听文件下载进度
    
    //                if (![NSThread isMainThread]) {
    //                    NSLog(@"当前线程：%@", [NSThread currentThread]);
    //                }
    // 进入主线程刷新UI
    __weak typeof(self) weakSelf = self; //避免block循环引用
    dispatch_async(dispatch_get_main_queue(), ^{
        //                    if ([NSThread isMainThread]) {
        //                        NSLog(@"主线程：%@", [NSThread currentThread]);
        //                    }
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.downloadProgress = 100 * totalBytesWritten / totalBytesExpectedToWrite;
        strongSelf.progressTextField.text = [NSString stringWithFormat:@"%lu%%", (unsigned long)strongSelf.downloadProgress];
    });
    //                NSLog(@"进度%.2f%%", (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite * 100);
    //                NSLog(@"已经接收到响应数据，数据长度为%lld字节...", totalBytesWritten);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    NSLog(@"expectedTotalBytes:%lld", expectedTotalBytes);
}

//下载完成的时候调用
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSLog(@"已经接收完所有响应数据，下载后的临时保存路径：%@", location);
    _downloadProgress = 0;
    [self saveResumeData];
    [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_NOT_STARTED];
    
    //剪切文件到最终位置
    //    NSString *filePath = [[self finallyFilePath] stringByAppendingPathComponent:downloadTask.response.suggestedFilename];
    //    [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:filePath] error:nil];
    //
    //    NSLog(@"移动至路径：%@", filePath);
}

//请求结束的时候调用（并不是发生错误的时候才调用）
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (!_resumeData) {
        [self changeDownloadButtonTitleByStatus:DOWNLOAD_STATUS_NOT_STARTED];
    }
    NSLog(@"---------");
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        // !!Note:-cancel method resumeData is empty!
        if (error.userInfo && [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData]) {
            //            if (self.downloadInfoDictionary == nil) {
            //                [self loadDownloadInfoDictionary];
            //            }
            //            NSLog(@"%d", task.taskIdentifier);
            //            // If you restart app,it will call this method with resumeData
            //            KDownloadInfo *di = [self downloadInfoWithTaskIdentifier:task.taskIdentifier];
            //            if (di) {
            //                di.resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
            //            }
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
