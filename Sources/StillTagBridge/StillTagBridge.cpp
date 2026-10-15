#include "StillTagBridge.h"
#include <flacfile.h>
#include <mpegfile.h>
#include <mp4file.h>
#include <mp4tag.h>
#include <mp4item.h>
#include <id3v2tag.h>
#include <id3v2header.h>
#include <unsynchronizedlyricsframe.h>
#include <apetag.h>
#include <xiphcomment.h>
#include <cstring>
#include <cstdio>
#include <exception>

static void clearID3(TagLib::ID3v2::Tag *tag) {
    if (!tag) return;
    tag->removeFrames("USLT");
    tag->removeFrames("SYLT");
}

extern "C" int still_write_lyrics(const char *path, const char *format, const char *lyrics,
                                  char *error, size_t capacity) {
    auto fail = [&](const char *message) {
        if (error && capacity) std::snprintf(error, capacity, "%s", message);
        return 0;
    };
    try {
        if (!path || !format) return fail("Invalid file path or format.");
        const TagLib::String text(lyrics ? lyrics : "", TagLib::String::UTF8);
        bool saved = false;
        if (std::strcmp(format, "flac") == 0) {
            TagLib::FLAC::File file(path, false);
            if (!file.isValid() || file.readOnly()) return fail("The FLAC file cannot be edited.");
            auto *tag = file.xiphComment(lyrics != nullptr);
            if (tag) {
                tag->removeFields("LYRICS");
                tag->removeFields("UNSYNCEDLYRICS");
                if (lyrics) tag->addField("LYRICS", text);
            }
            clearID3(file.ID3v2Tag(false));
            saved = file.save();
        } else if (std::strcmp(format, "mp3") == 0) {
            TagLib::MPEG::File file(path, false);
            if (!file.isValid() || file.readOnly()) return fail("The MP3 file cannot be edited.");
            auto *tag = file.ID3v2Tag(lyrics != nullptr);
            clearID3(tag);
            if (auto *ape = file.APETag(false)) {
                ape->removeItem("LYRICS");
                ape->removeItem("UNSYNCEDLYRICS");
            }
            if (lyrics) {
                auto *frame = new TagLib::ID3v2::UnsynchronizedLyricsFrame(TagLib::String::UTF8);
                frame->setLanguage("und");
                frame->setText(text);
                tag->addFrame(frame);
            }
            // Preserve existing tag families without copying fields between them.
            const auto version = tag && tag->header()->majorVersion() == 3 ? TagLib::ID3v2::v3 : TagLib::ID3v2::v4;
            saved = file.save(TagLib::MPEG::File::AllTags, TagLib::File::StripNone,
                              version, TagLib::File::DoNotDuplicate);
        } else if (std::strcmp(format, "m4a") == 0 || std::strcmp(format, "mp4") == 0) {
            TagLib::MP4::File file(path, false);
            if (!file.isValid() || file.readOnly()) return fail("The M4A file cannot be edited.");
            const TagLib::String key("\251lyr", TagLib::String::Latin1);
            file.tag()->removeItem(key);
            if (lyrics) file.tag()->setItem(key, TagLib::MP4::Item(TagLib::StringList(text)));
            saved = file.save();
        } else return fail("Embedded lyrics editing supports FLAC, MP3 and M4A only.");
        return saved ? 1 : fail("The metadata library could not save this file.");
    } catch (const std::exception &) {
        return fail("The metadata library could not process this file.");
    } catch (...) {
        return fail("Unexpected metadata-writing failure.");
    }
}
