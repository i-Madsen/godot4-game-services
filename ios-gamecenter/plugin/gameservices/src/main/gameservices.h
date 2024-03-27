//
//  admob.h
//  admob
//
//  Created by Gustavo Maciel on 16/01/21.
//

#ifndef gameservices_plugin_implementation_h
    #define gameservices_plugin_implementation_h

    #include "core/version.h"

    #if VERSION_MAJOR == 4
    #include "core/object/class_db.h"
    #include "core/io/image.h"
    #else
    #include "core/object.h"
    #include "core/image.h"
    #endif

    #import <UIKit/UIKit.h>
    #import <GameKit/GameKit.h>
    
    @class GameServicesHelper;

    class GameServices : public Object {
        GDCLASS(GameServices, Object);

        static GameServices *instance;

        bool initialized;

        GameServicesHelper *gameServicesHelper;

        NSMutableDictionary *all_leaderboards;
        GKLeaderboard *current_leaderboard;
        int current_leaderboard_page_size;
        int current_leaderboard_players;
        int current_leaderboard_time;
        int current_leaderboard_range_start;
        
        NSMutableDictionary *all_friends;
        
        //List<Variant> pending_events;

    protected:
        static void _bind_methods();

    public:

        String get_service_name();

        void initialize();

        bool can_sign_in();
        void sign_in();

        void show_leaderboard(const String &leaderboard_id, int players, int time);
        void show_all_leaderboards();

        void fetch_top_scores_from_set(const String &set_id, const String &leaderboard_id, int page_size, int players, int time, int range_start = 1);
        void fetch_top_scores(const String &leaderboard_id, int page_size, int players, int time, int range_start = 1);
        void fetch_next_scores();

        void submit_score(const String &leaderboard_id, int score);

        Error award_achievement(Dictionary p_params);
        void request_achievement_descriptions();
        void request_achievements() ;
        void reset_achievements();
        
        //int get_pending_event_count();
        //Variant pop_pending_event();
        
        void get_friends_authorization_status();
        void load_friends();
        void fetch_friend_avatar(const String &player_id);

        
        GameServices();
        ~GameServices();

        static GameServices *get_singleton();

    private:

        void fetch_leaderboard(GKLeaderboardSet *leaderboardSet, const String &leaderboard_id, const String &error_signal, void (^completion)(GKLeaderboard * leaderboard));
        void fetch_scores();

        CGImageRef newRGBA8CGImageFromUIImage(UIImage* image);
        
        Dictionary dict_from_player(GKPlayer *player);
        Dictionary dict_from_leaderboard(GKLeaderboard *leaderboard);
        Dictionary dict_from_score(GKLeaderboardEntry *score, bool for_local_player);

        GKLeaderboardPlayerScope players_scope_from_int(int players);
        GKLeaderboardTimeScope time_scope_from_int(int time);
    };

#endif /* gameservices_plugin_implementation_h */
