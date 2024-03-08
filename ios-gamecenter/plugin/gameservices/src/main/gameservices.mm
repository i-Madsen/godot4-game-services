//
//  admob.m
//  admob
//
//  Created by Gustavo Maciel on 16/01/21.
//

#include "core/config/project_settings.h"
#include "core/object/class_db.h"

#include "gameservices.h"
#import "GameServicesHelper.h"


#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
typedef PackedInt32Array GodotIntArray;
typedef PackedFloat32Array GodotFloatArray;
#else
typedef PoolStringArray GodotStringArray;
typedef PoolIntArray GodotIntArray;
typedef PoolRealArray GodotFloatArray;
#endif

GameServices *GameServices::instance = NULL;

GameServices::GameServices() {

    initialized = false;
    
    // GKLeaderboard is a query object, so calling from the objects should always give up-to-date scores
    all_leaderboards = [[NSMutableDictionary alloc] init];
    current_leaderboard = nil;
    current_leaderboard_page_size = 0;
    current_leaderboard_players = 0;
    current_leaderboard_time = 0;
    current_leaderboard_range_start = 0;
    
    all_friends = [[NSMutableDictionary alloc] init];
    
    ERR_FAIL_COND(instance != NULL);
    
    instance = this;
    NSLog(@"initialize gameservices");
    
    gameServicesHelper = [[GameServicesHelper alloc] initWithGameServices:this];
}

GameServices::~GameServices() {
    if (instance == this) {
        instance = NULL;
        gameServicesHelper = nil;
    }
    NSLog(@"deinitialize gameservices");
}

GameServices *GameServices::get_singleton() {
    return instance;
};

String GameServices::get_service_name()
{
    return String("Game Center");
}

void GameServices::initialize() {

    if (instance != this || initialized)
    {
        NSLog(@"GameServices module already initialized");
        return;
    }
    NSLog(@"GameServices module will try to initialize now");
    
    [GKLocalPlayer local].authenticateHandler = (^(UIViewController *viewController, NSError * error) {

        if (error) {
            emit_signal("authorization_complete", false, Dictionary());
            emit_signal("authorization_failed", [error.localizedDescription UTF8String]);
            return;
        }

        if (viewController) {
            [gameServicesHelper presentViewController: viewController];
            return;
        }

        GKLocalPlayer *player = [GKLocalPlayer local];
        emit_signal("authorization_complete", player.isAuthenticated, dict_from_player(player));
    });
}

bool GameServices::can_sign_in() {
    return false; // Game Center does not allow us to trigger the sign-in controller again
}

void GameServices::sign_in() {
    // Shouldn't be called on iOS, but if it is at least we can return a sensible result
    GKLocalPlayer *player = [GKLocalPlayer local];
    bool is_authenticated = player.isAuthenticated;
    Dictionary player_info = is_authenticated ? dict_from_player(player) : Dictionary();
    emit_signal("authorization_complete", is_authenticated, player_info);
}

// MARK: Leaderboards

// TODO: Need to add a 'from_set' variant if you want to use this function with leaderboards that are in sets
void GameServices::show_leaderboard(const String &leaderboard_id, int players, int time)
{
    fetch_leaderboard(nil, leaderboard_id, "show_leaderboard_failed", ^(GKLeaderboard *leaderboard) {
        NSString *leaderboardID = leaderboard.baseLeaderboardID;
        GKGameCenterViewController *viewController = [[GKGameCenterViewController alloc] initWithLeaderboardID:leaderboardID playerScope:players_scope_from_int(players) timeScope:time_scope_from_int(time)];
        viewController.gameCenterDelegate = gameServicesHelper;
        [gameServicesHelper presentViewController:viewController forLeaderboardID:leaderboardID];
        emit_signal("show_leaderboard_complete", leaderboardID.UTF8String);
    });
}

void GameServices::show_all_leaderboards()
{
    //emit_signal("debug_message", "called show_all_leaderboards()");
    GKGameCenterViewController *viewController = [[GKGameCenterViewController alloc] initWithState:GKGameCenterViewControllerStateLeaderboards];
    viewController.gameCenterDelegate = gameServicesHelper;
    [gameServicesHelper presentViewController:viewController forLeaderboardID:@""];
    emit_signal("show_leaderboard_complete", "");
}

void GameServices::fetch_top_scores_from_set(const String &set_id, const String &leaderboard_id, int page_size, int players, int time) {
    NSString *leaderboardID = [NSString stringWithCString:leaderboard_id.utf8().get_data() encoding:NSUTF8StringEncoding];
    NSString *errorSignal = @"fetch_scores_failed";
    //NSLog(@"Fetching leaderboard_id: %@", leaderboardID);
    void (^completion)(GKLeaderboard *leaderboard) = ^(GKLeaderboard *leaderboard) {

        current_leaderboard = leaderboard;
        current_leaderboard_page_size = page_size;
        current_leaderboard_players = players;
        current_leaderboard_time = time;
        current_leaderboard_range_start = 1;
        
        fetch_scores();
    };
    
    // Have we already fetched the leaderboards?
    if (all_leaderboards != nil) {
        if ([all_leaderboards objectForKey:leaderboardID]){
            //NSLog(@"Found in all_leaderboards...");
            completion([all_leaderboards objectForKey:leaderboardID]);
            
            return;
        }
    }
    
    
    NSString *setID = [NSString stringWithCString:set_id.utf8().get_data() encoding:NSUTF8StringEncoding];
    //NSLog(@"(Not found in all_leaderboards) Fetching from set_id: %@", setID);
    
    // Get the leaderboard set
    [GKLeaderboardSet loadLeaderboardSetsWithCompletionHandler:^(NSArray *leaderboardSets, NSError *error) {
        //NSLog(@"In loadLeaderboardSetsWithCompletionHandler...");
        if (error) {
            emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, error.localizedDescription.UTF8String);
            return;
        }
        
        GKLeaderboardSet *theLeaderboardSet = nil;
        
        for (GKLeaderboardSet *leaderboardSet in leaderboardSets) {
            if ([leaderboardSet.identifier isEqualToString:setID]) {
                //NSLog(@"found matching leaderboard set!");
                theLeaderboardSet = leaderboardSet;
                break;
            }
        }
        
        if (theLeaderboardSet == nil) {
            emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, "leaderboard not found");
            return;
        }
        
        // Get all leaderboards in this set
        [theLeaderboardSet loadLeaderboardsWithHandler:^(NSArray *leaderboards, NSError *error) {
            //NSLog(@"In loadLeaderboardsWithHandler for the set...");
            if (error) {
                emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, error.localizedDescription.UTF8String);
                return;
            }
            
            //NSLog(@"leaderboards: %@", leaderboards);

            if (leaderboards == nil || leaderboards.count == 0) {
                emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, "leaderboard not found");
                return;
            }
            
            
            
            GKLeaderboard *theLeaderboard = nil;
            
            for (GKLeaderboard *leaderboard in leaderboards) {
                if ([leaderboard.baseLeaderboardID isEqualToString:leaderboardID]) {
                    //NSLog(@"found matching leaderboard");
                    theLeaderboard = leaderboard;
                }
                // If we're at this point, that means we haven't stored the GKLeaderboard objects yet for this set, so go ahead and save them all
                [all_leaderboards setValue:leaderboard forKey:leaderboard.baseLeaderboardID];
            }
            
            if (theLeaderboard == nil) {
                emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, "leaderboard not found");
                return;
            }
            //NSLog(@"Calling completion from end...");
            completion(theLeaderboard);
        }];
    }];
}

void GameServices::fetch_top_scores(const String &leaderboard_id, int page_size, int players, int time) {
    
    fetch_leaderboard(nil, leaderboard_id, "fetch_scores_failed", ^(GKLeaderboard *leaderboard) {

        current_leaderboard = leaderboard;
        current_leaderboard_page_size = page_size;
        current_leaderboard_players = players;
        current_leaderboard_time = time;
        current_leaderboard_range_start = 1;
        
        fetch_scores();
    });
}

void GameServices::fetch_next_scores() {
    
    if (current_leaderboard == nil) {
        emit_signal("fetch_scores_failed", "", "fetch_next before fetch_top");
        return;
    }
    
    fetch_scores();
}

void GameServices::submit_score(const String &leaderboard_id, int score) {

    // For below, because String isn't being captured in blocks
    NSString *leaderboardID = [NSString stringWithCString:leaderboard_id.utf8().get_data() encoding:NSUTF8StringEncoding];

    // Should only be submitting scores to leaderboards we've already saved
    fetch_leaderboard(nil, leaderboard_id, "submit_score_failed", ^(GKLeaderboard *leaderboard) {
        [leaderboard submitScore:score context:0 player:[GKLocalPlayer local] completionHandler:^(NSError * _Nullable error) {
            if (error) {
                emit_signal("submit_score_failed", leaderboardID.UTF8String, error.localizedDescription.UTF8String);
            } else {
                emit_signal("submit_score_complete", leaderboardID.UTF8String);
            }
        }];
    });
}

// MARK: Leaderboard helpers

void GameServices::fetch_leaderboard(GKLeaderboardSet *leaderboardSet, const String &leaderboard_id, const String &error_signal, void (^completion)(GKLeaderboard *leaderboard)) {
    
    NSString *leaderboardID = [NSString stringWithCString:leaderboard_id.utf8().get_data() encoding:NSUTF8StringEncoding];
    NSString *errorSignal = [NSString stringWithCString:error_signal.utf8().get_data() encoding:NSUTF8StringEncoding];
    
    // Have we already fetched the leaderboards?
    if (all_leaderboards != nil) {
        if ([all_leaderboards objectForKey:leaderboardID]){
            completion([all_leaderboards objectForKey:leaderboardID]);
            return;
        }
    }
    
    NSArray<NSString *> *leaderboardIDs =  [NSArray arrayWithObject:leaderboardID];
    
    [GKLeaderboard loadLeaderboardsWithIDs:leaderboardIDs completionHandler:^(NSArray *leaderboards, NSError *error) {
        
        if (error) {
            emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, error.localizedDescription.UTF8String);
            return;
        }
        
        //NSLog(@"leaderboards: %@", leaderboards);

        if (leaderboards == nil || leaderboards.count == 0) {
            emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, "leaderboard not found");
            return;
        }
        
        
        
        GKLeaderboard *theLeaderboard = nil;
        
        for (GKLeaderboard *leaderboard in leaderboards) {
            if ([leaderboard.baseLeaderboardID isEqualToString:leaderboardID]) {
                //NSLog(@"found matching leaderboard");
                theLeaderboard = leaderboard;
                break;
            }
        }
        
        if (theLeaderboard == nil) {
            emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, "leaderboard not found");
            return;
        }
        
        [all_leaderboards setValue:theLeaderboard forKey:leaderboardID];
        
        completion(theLeaderboard);
    }];
}

#define min(a,b) ((a)<(b)?(a):(b))

void GameServices::fetch_scores() {
    
    // calculate how many results we should request. assumes this will never be negative
    int range_length = min(current_leaderboard_page_size, 101 - current_leaderboard_range_start); // 101 to allow for results 1-100 inclusive
    NSRange range = NSMakeRange(current_leaderboard_range_start, range_length);
    
    [current_leaderboard loadEntriesForPlayerScope:players_scope_from_int(current_leaderboard_players)
                                         timeScope:time_scope_from_int(current_leaderboard_time)
                                             range:range
                                 completionHandler:^(GKLeaderboardEntry * _Nullable_result localPlayerEntry, NSArray<GKLeaderboardEntry *> * _Nullable entries, NSInteger totalPlayerCount, NSError * _Nullable error) {
        if (error) {
            emit_signal("fetch_scores_failed", current_leaderboard.baseLeaderboardID.UTF8String, error.localizedDescription.UTF8String);
            return;
        }
        
        Dictionary leaderboard_info = dict_from_leaderboard(current_leaderboard);
        Dictionary player_score = dict_from_score(localPlayerEntry, true);
        
        Dictionary scores = Dictionary();
        int i = 0;
        for (GKLeaderboardEntry *score in entries) {
            scores[@(i++).stringValue.UTF8String] = dict_from_score(score, false);
        }
        
        current_leaderboard_range_start += entries.count; // or i would work too
        
        bool more_available = entries.count == current_leaderboard_page_size && current_leaderboard_range_start < 100 && current_leaderboard_range_start < totalPlayerCount;
        if (!more_available) {
            current_leaderboard = nil; // prevents fetch_next_scores() if called again
        }
        
        emit_signal("fetch_scores_complete", leaderboard_info, player_score, scores, more_available);
    }];
}


// #####################################################################################################################################
// Achievements
// #####################################################################################################################################
Error GameServices::award_achievement(Dictionary p_params) {
    ERR_FAIL_COND_V(!p_params.has("name") || !p_params.has("progress"), ERR_INVALID_PARAMETER);
    String name = p_params["name"];
    float progress = p_params["progress"];

    NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
    GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:name_str];
    ERR_FAIL_COND_V(!achievement, FAILED);

    ERR_FAIL_COND_V([GKAchievement respondsToSelector:@selector(reportAchievements)], ERR_UNAVAILABLE);

    achievement.percentComplete = progress;
    achievement.showsCompletionBanner = NO;
    if (p_params.has("show_completion_banner")) {
        achievement.showsCompletionBanner = p_params["show_completion_banner"] ? YES : NO;
    }

    [GKAchievement reportAchievements:@[ achievement ]
                withCompletionHandler:^(NSError *error) {
                    Dictionary ret;
                    if (error == nil) {
                        ret["result"] = "ok";
                    } else {
                        ret["result"] = "error";
                        ret["error_code"] = (int64_t)error.code;
                    };

                    emit_signal("award_achievement_complete", ret);
                }];

    return OK;
};

void GameServices::request_achievement_descriptions() {
    [GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:^(NSArray *descriptions, NSError *error) {
        Dictionary ret;
        if (error == nil) {
            ret["result"] = "ok";
            GodotStringArray names;
            GodotStringArray titles;
            GodotStringArray unachieved_descriptions;
            GodotStringArray achieved_descriptions;
            GodotIntArray maximum_points;
            Array hidden;
            Array replayable;

            for (NSUInteger i = 0; i < [descriptions count]; i++) {

                GKAchievementDescription *description = [descriptions objectAtIndex:i];

                const char *str = [description.identifier UTF8String];
                names.push_back(String::utf8(str != NULL ? str : ""));

                str = [description.title UTF8String];
                titles.push_back(String::utf8(str != NULL ? str : ""));

                str = [description.unachievedDescription UTF8String];
                unachieved_descriptions.push_back(String::utf8(str != NULL ? str : ""));

                str = [description.achievedDescription UTF8String];
                achieved_descriptions.push_back(String::utf8(str != NULL ? str : ""));

                maximum_points.push_back(description.maximumPoints);

                hidden.push_back(description.hidden == YES);

                replayable.push_back(description.replayable == YES);
            }

            ret["names"] = names;
            ret["titles"] = titles;
            ret["unachieved_descriptions"] = unachieved_descriptions;
            ret["achieved_descriptions"] = achieved_descriptions;
            ret["maximum_points"] = maximum_points;
            ret["hidden"] = hidden;
            ret["replayable"] = replayable;

        } else {
            ret["result"] = "error";
            ret["error_code"] = (int64_t)error.code;
        };

        emit_signal("request_achievement_descriptions_complete", ret);
    }];
};

void GameServices::request_achievements() {
    [GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
        Dictionary ret;
        if (error == nil) {
            ret["result"] = "ok";
            GodotStringArray names;
            GodotFloatArray percentages;

            for (NSUInteger i = 0; i < [achievements count]; i++) {

                GKAchievement *achievement = [achievements objectAtIndex:i];
                const char *str = [achievement.identifier UTF8String];
                names.push_back(String::utf8(str != NULL ? str : ""));

                percentages.push_back(achievement.percentComplete);
            }

            ret["names"] = names;
            ret["progress"] = percentages;

        } else {
            ret["result"] = "error";
            ret["error_code"] = (int64_t)error.code;
        };

        emit_signal("request_achievements_complete", ret);
    }];
};

void GameServices::reset_achievements() {
    [GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
        Dictionary ret;
        if (error == nil) {
            ret["result"] = "ok";
        } else {
            ret["result"] = "error";
            ret["error_code"] = (int64_t)error.code;
        };

        emit_signal("reset_achievements_complete", ret);
    }];
};



// #####################################################################################################################################
// Friends
// #####################################################################################################################################
void GameServices::get_friends_authorization_status() {
    [GKLocalPlayer.local loadFriendsAuthorizationStatus:^(GKFriendsAuthorizationStatus authorizationStatus, NSError *error) {
        if (error == nil) {
            // notDetermined = 0, restricted = 1, denied = 2, authorized = 3
            emit_signal("get_friends_authorization_status_complete", authorizationStatus);
        } else {
            emit_signal("get_friends_authorization_status_failed", error.localizedDescription.UTF8String);
        };
    }];
}

void GameServices::load_friends() {
    [GKLocalPlayer.local loadFriends:^(NSArray *friends, NSError *error) {
        if (error == nil) {
            Dictionary friend_dict = Dictionary();
            
            for (NSUInteger i = 0; i < friends.count; i++) {
                [all_friends setValue:friends[i] forKey:[friends[i] gamePlayerID]];
                friend_dict[@(i).stringValue.UTF8String] = dict_from_player(friends[i]);
            }
            emit_signal("load_friends_complete", friend_dict);
            
        } else {
            emit_signal("load_friends_failed", error.localizedDescription.UTF8String);
        };
    }];
}

void GameServices::fetch_friend_avatar(const String &player_id) {
    NSString *playerID = [NSString stringWithCString:player_id.utf8().get_data() encoding:NSUTF8StringEncoding];
    GKPlayer* player;
    
    if ([playerID isEqualToString: GKLocalPlayer.local.gamePlayerID]) {
        player = GKLocalPlayer.local;
        //NSLog(@"Fetching local player avatar...");
    }
    else {
        if (all_friends[playerID])
        {
            player = all_friends[playerID];
            //NSLog(@"Fetching friend avatar...");
        }
        else
        {
            //NSLog(@"Did not find friend id.");
            emit_signal("fetch_friend_avatar_failed", "Did not find friend with id: " + player_id);
            return;
        }
    }
    
    // Get player's avatar photo
    [player loadPhotoForSize:(GKPhotoSizeNormal) withCompletionHandler:^(UIImage * _Nullable photo, NSError * _Nullable error) {
        if (photo) {
            //NSLog(@"Got photo...");
            CGImageRef cgImage = newRGBA8CGImageFromUIImage(photo);
            
            if (cgImage) {
                //NSLog(@"Converted to CGImageRef...");
                CGDataProviderRef provider = CGImageGetDataProvider(cgImage);
                CFDataRef bmp = CGDataProviderCopyData(provider);
                const unsigned char *data = CFDataGetBytePtr(bmp);
                CFIndex length = CFDataGetLength(bmp);
                
                if (data) {
                    //NSLog(@"Converted into data...");
                    Ref<Image> img;
                #if VERSION_MAJOR == 4
                    Vector<uint8_t> img_data;
                    img_data.resize(length);
                    uint8_t* w = img_data.ptrw();
                    memcpy(w, data, length);
                    
                    img.instantiate();
                    img->set_data(photo.size.width * photo.scale, photo.size.height * photo.scale, 0, Image::FORMAT_RGBA8, img_data);
                #else
                    PoolVector<uint8_t> img_data;
                    img_data.resize(length);
                    PoolVector<uint8_t>::Write w = img_data.write();
                    memcpy(w.ptr(), data, length);
                    
                    img.instance();
                    img->create(image.size.width * image.scale, image.size.height * image.scale, 0, Image::FORMAT_RGBA8, img_data);
                #endif
                    //NSLog(@"Emitting fetch_friend_avatar_complete...");
                    // Sending back the player's display name instead of id since the friend ids were not consistent with the ones sent back from leaderboards
                    // This may vary from app to app, but display name *should* always work here regardless
                    emit_signal("fetch_friend_avatar_complete", player.displayName.UTF8String, img);
                }
                else {
                    //NSLog(@"Conversion into data failed...");
                    emit_signal("fetch_friend_avatar_failed", @"Conversion into data failed...");
                }
                
                CFRelease(bmp);
                CGImageRelease(cgImage);
            }
            else
            {
                //NSLog(@"Conversion to CGImageRef was nil...");
                emit_signal("fetch_friend_avatar_failed", @"Conversion to CGImageRef was nil...");
            }
        } else {
            //NSLog(@"Photo returned nil...");
            emit_signal("fetch_friend_avatar_failed", error.localizedDescription.UTF8String);
        }
    }];
}


// #####################################################################################################################################
// Private helpers
// #####################################################################################################################################
CGImageRef GameServices::newRGBA8CGImageFromUIImage(UIImage* image) {
    size_t bitsPerPixel = 32;
    size_t bitsPerComponent = 8;
    size_t bytesPerPixel = bitsPerPixel / bitsPerComponent;

    size_t width = image.size.width;
    size_t height = image.size.height;
    UIImageOrientation orientation = image.imageOrientation;

    size_t bytesPerRow = width * bytesPerPixel;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

    if (!colorSpace) {
        NSLog(@"Error allocating color space RGB");
        return NULL;
    }

    CGAffineTransform transform = CGAffineTransformIdentity;

    switch (orientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, width, height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        default:
            break;
    }

    switch (orientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        default:
            break;
    }

    CGContextRef context = CGBitmapContextCreate(NULL,
            width,
            height,
            bitsPerComponent,
            bytesPerRow,
            colorSpace,
            kCGImageAlphaPremultipliedLast);

    CGImageRef newCGImage = NULL;

    if (!context) {
        NSLog(@"Bitmap context not created");
    } else {

        CGContextConcatCTM(context, transform);

        switch (orientation) {
            case UIImageOrientationLeft:
            case UIImageOrientationLeftMirrored:
            case UIImageOrientationRight:
            case UIImageOrientationRightMirrored:
                CGContextDrawImage(context, CGRectMake(0, 0, height, width), [image CGImage]);
                break;
            default:
                CGContextDrawImage(context, CGRectMake(0, 0, width, height), [image CGImage]);
                break;
        }

        newCGImage = CGBitmapContextCreateImage(context);
    }

    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);

    return newCGImage;
}


Dictionary GameServices::dict_from_player(GKPlayer *player) {
    Dictionary dict = Dictionary();
    dict["display_name"] = player.displayName.UTF8String;
    dict["id"] = player.gamePlayerID.UTF8String;
    dict["is_local_player"] = [player.gamePlayerID isEqualToString: GKLocalPlayer.local.gamePlayerID];
    return dict;
}

Dictionary GameServices::dict_from_leaderboard(GKLeaderboard *leaderboard) {
    Dictionary dict = Dictionary();
    dict["id"] = leaderboard.baseLeaderboardID.UTF8String;
    dict["display_name"] = leaderboard.title ? leaderboard.title.UTF8String : "";
    return dict;
}

Dictionary GameServices::dict_from_score(GKLeaderboardEntry *score, bool for_local_player) {
    Dictionary dict = Dictionary();
    // ignore eg. the local player score when they haven't submitted one for this leaderboard
    if (score && score.rank != 0) {
        dict["rank"] = (int)score.rank;
        dict["score"] = (int)score.score;
        dict["formatted_score"] = score.formattedScore.UTF8String;
        // the .player property of the localPlayerEntry will be an anonymous user if their score is
        //  not included in the set returned. this hack allows us to ensure that the player's info
        //  is always returned in this scenario
        dict["player"] = dict_from_player(for_local_player ? GKLocalPlayer.local : score.player);
    }
    return dict;
}

GKLeaderboardPlayerScope GameServices::players_scope_from_int(int players) {
    // Roughly follows the Google Play Services scheme where:
    //  0 = COLLECTION_PUBLIC
    //  3 = COLLECTION_FRIENDS
    return players == 0 ? GKLeaderboardPlayerScopeGlobal : GKLeaderboardPlayerScopeFriendsOnly;
}

GKLeaderboardTimeScope GameServices::time_scope_from_int(int time) {
    // Follows the Google Play Services scheme where:
    //  0 = TIME_SPAN_DAILY
    //  1 = TIME_SPAN_WEEKLY
    //  2 = TIME_SPAN_ALL_TIME
    switch (time) {
        case 0: return GKLeaderboardTimeScopeToday;
        case 1: return GKLeaderboardTimeScopeWeek;
        default: return GKLeaderboardTimeScopeAllTime;
    }
}

void GameServices::_bind_methods() {
    
    // Methods
    
    ClassDB::bind_method("get_service_name", &GameServices::get_service_name);
    
    ClassDB::bind_method("initialize", &GameServices::initialize);
    
    ClassDB::bind_method("can_sign_in", &GameServices::can_sign_in);
    ClassDB::bind_method("sign_in", &GameServices::sign_in);
    
    ClassDB::bind_method("show_leaderboard", &GameServices::show_leaderboard);
    ClassDB::bind_method("show_all_leaderboards", &GameServices::show_all_leaderboards);
    
    ClassDB::bind_method("fetch_top_scores_from_set", &GameServices::fetch_top_scores_from_set);
    ClassDB::bind_method("fetch_top_scores", &GameServices::fetch_top_scores);
    ClassDB::bind_method("fetch_next_scores", &GameServices::fetch_next_scores);
    
    ClassDB::bind_method("submit_score", &GameServices::submit_score);
    
    ClassDB::bind_method(D_METHOD("award_achievement", "achievement"), &GameServices::award_achievement);
    ClassDB::bind_method("reset_achievements", &GameServices::reset_achievements);
    ClassDB::bind_method("request_achievements", &GameServices::request_achievements);
    ClassDB::bind_method("request_achievement_descriptions", &GameServices::request_achievement_descriptions);
    
    ClassDB::bind_method("get_friends_authorization_status", &GameServices::get_friends_authorization_status);
    ClassDB::bind_method("load_friends", &GameServices::load_friends);
    ClassDB::bind_method("fetch_friend_avatar", &GameServices::fetch_friend_avatar);
    
    // Signals
    
    ADD_SIGNAL(MethodInfo("debug_message", PropertyInfo(Variant::STRING, "message")));
    
    // initialize()
    // sign_in()
    ADD_SIGNAL(MethodInfo("authorization_complete", PropertyInfo(Variant::BOOL, "signed_in"), PropertyInfo(Variant::DICTIONARY, "player_info")));
    ADD_SIGNAL(MethodInfo("authorization_failed", PropertyInfo(Variant::STRING, "error_message")));
    
    // show_leaderboard()
    // show_all_leaderboards()
    ADD_SIGNAL(MethodInfo("show_leaderboard_complete", PropertyInfo(Variant::STRING, "leaderboard_id")));
    ADD_SIGNAL(MethodInfo("show_leaderboard_failed", PropertyInfo(Variant::STRING, "leaderboard_id"), PropertyInfo(Variant::STRING, "error_message")));
    ADD_SIGNAL(MethodInfo("show_leaderboard_dismissed", PropertyInfo(Variant::STRING, "leaderboard_id")));
    
    // fetch_?_scores()
    ADD_SIGNAL(MethodInfo("fetch_scores_complete", PropertyInfo(Variant::DICTIONARY, "leaderboard_info"), PropertyInfo(Variant::DICTIONARY, "player_score"), PropertyInfo(Variant::DICTIONARY, "scores"), PropertyInfo(Variant::BOOL, "more_available")));
    ADD_SIGNAL(MethodInfo("fetch_scores_failed", PropertyInfo(Variant::STRING, "leaderboard_id"), PropertyInfo(Variant::STRING, "error_message")));
    
    // submit_score()
    ADD_SIGNAL(MethodInfo("submit_score_complete", PropertyInfo(Variant::STRING, "leaderboard_id")));
    ADD_SIGNAL(MethodInfo("submit_score_failed", PropertyInfo(Variant::STRING, "leaderboard_id"), PropertyInfo(Variant::STRING, "error_message")));
    
    
    // award_achievement()
    ADD_SIGNAL(MethodInfo("award_achievement_complete", PropertyInfo(Variant::DICTIONARY, "ret")));
    
    // request_achievement_descriptions()
    ADD_SIGNAL(MethodInfo("request_achievement_descriptions_complete", PropertyInfo(Variant::DICTIONARY, "ret")));
    
    // request_achievements()
    ADD_SIGNAL(MethodInfo("request_achievements_complete", PropertyInfo(Variant::DICTIONARY, "ret")));
    
    // reset_achievements()
    ADD_SIGNAL(MethodInfo("reset_achievements_complete", PropertyInfo(Variant::DICTIONARY, "ret")));
    
    // Getting friend list authorization status
    ADD_SIGNAL(MethodInfo("get_friends_authorization_status_complete", PropertyInfo(Variant::INT, "authorization_enum")));
    ADD_SIGNAL(MethodInfo("get_friends_authorization_status_failed", PropertyInfo(Variant::STRING, "error_message")));
    
    // Getting friends
    ADD_SIGNAL(MethodInfo("load_friends_complete", PropertyInfo(Variant::DICTIONARY, "friend_dict")));
    ADD_SIGNAL(MethodInfo("load_friends_failed", PropertyInfo(Variant::STRING, "error_message")));
    
    // Getting friend avatar images
    ADD_SIGNAL(MethodInfo("fetch_friend_avatar_complete", PropertyInfo(Variant::STRING, "friend_name"), PropertyInfo(Variant::OBJECT, "friend_img")));
    ADD_SIGNAL(MethodInfo("fetch_friend_avatar_failed", PropertyInfo(Variant::STRING, "error_message")));
    
}
