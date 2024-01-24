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
    
    all_leaderboards = [[NSMutableDictionary alloc] init];
    current_leaderboard = nil;
    current_leaderboard_page_size = 0;
    current_leaderboard_players = 0;
    current_leaderboard_time = 0;
    current_leaderboard_range_start = 0;
    
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

void GameServices::show_leaderboard(const String &leaderboard_id, int players, int time)
{
    fetch_leaderboard(leaderboard_id, "show_leaderboard_failed", ^(GKLeaderboard *leaderboard) {
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

void GameServices::fetch_top_scores(const String &leaderboard_id, int page_size, int players, int time) {
    
    fetch_leaderboard(leaderboard_id, "fetch_scores_failed", ^(GKLeaderboard *leaderboard) {

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

    fetch_leaderboard(leaderboard_id, "submit_score_failed", ^(GKLeaderboard *leaderboard) {
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

void GameServices::fetch_leaderboard(const String &leaderboard_id, const String &error_signal, void (^completion)(GKLeaderboard *leaderboard)) {
    
    NSString *leaderboardID = [NSString stringWithCString:leaderboard_id.utf8().get_data() encoding:NSUTF8StringEncoding];
    NSString *errorSignal = [NSString stringWithCString:error_signal.utf8().get_data() encoding:NSUTF8StringEncoding];
    
    // Have we already fetched the leaderboards?
    /*if (all_leaderboards != nil) {
        GKLeaderboard *theLeaderboard = nil;
        for (GKLeaderboard *leaderboard in all_leaderboards) {
            if ([leaderboard.baseLeaderboardID isEqualToString:leaderboardID]) {
                //NSLog(@"found matching leaderboard");
                theLeaderboard = leaderboard;
                break;
            }
        }
        
        if (theLeaderboard) {
            completion(theLeaderboard);
        } else {
            emit_signal(errorSignal.UTF8String, leaderboardID.UTF8String, "leaderboard not found");
        }
        
        return;
    }*/
    
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
// TODO: Instead of doing the pending_events.pushback in completion handlers, we should make signals like the other methods
//#####################################################################################################################################
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
 
Dictionary GameServices::dict_from_player(GKPlayer *player) {
    Dictionary dict = Dictionary();
    dict["display_name"] = player.displayName.UTF8String;
    if (@available(iOS 13.0, *)) {
        dict["id"] = player.gamePlayerID.UTF8String;
        dict["is_local_player"] = [player.gamePlayerID isEqualToString: GKLocalPlayer.local.gamePlayerID];
    } else {
        dict["id"] = player.gamePlayerID.UTF8String;
        dict["is_local_player"] = [player.gamePlayerID isEqualToString: GKLocalPlayer.local.gamePlayerID];
    }
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
    
    ClassDB::bind_method("fetch_top_scores", &GameServices::fetch_top_scores);
    ClassDB::bind_method("fetch_next_scores", &GameServices::fetch_next_scores);
    
    ClassDB::bind_method("submit_score", &GameServices::submit_score);
    
    ClassDB::bind_method(D_METHOD("award_achievement", "achievement"), &GameServices::award_achievement);
    ClassDB::bind_method("reset_achievements", &GameServices::reset_achievements);
    ClassDB::bind_method("request_achievements", &GameServices::request_achievements);
    ClassDB::bind_method("request_achievement_descriptions", &GameServices::request_achievement_descriptions);
    
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
}
