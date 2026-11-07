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

#include <fileref.h>
#include <tpropertymap.h>
#include <attachedpictureframe.h>
#include <flacpicture.h>
#include <mp4coverart.h>

extern "C" int still_read_property(const char *path, const char *key, char *value, size_t capacity) {
    try {
        TagLib::FileRef file(path, true, TagLib::AudioProperties::Accurate);
        if(file.isNull() || !file.file()->isValid()) return 0;
        std::string result;
        auto *audio = file.audioProperties();
        if(std::strcmp(key, "_DURATION") == 0 && audio) result = std::to_string(audio->lengthInMilliseconds() / 1000.0);
        else if(std::strcmp(key, "_CHANNELS") == 0 && audio) result = std::to_string(audio->channels());
        else if(std::strcmp(key, "_RATE") == 0 && audio) result = std::to_string(audio->sampleRate());
        else if(std::strcmp(key, "_BITRATE") == 0 && audio) result = std::to_string(audio->bitrate() * 1000);
        else {
            const auto properties = file.file()->properties();
            TagLib::String name(key, TagLib::String::UTF8);
            if(!properties.contains(name)) return 0;
            result = properties[name].toString("; ").to8Bit(true);
        }
        if(result.size() >= capacity) return 0;
        std::snprintf(value, capacity, "%s", result.c_str());
        return 1;
    } catch (...) { return 0; }
}

extern "C" int still_write_property(const char *path, const char *key, const char *value) {
    try {
        TagLib::FileRef file(path, false);
        if(file.isNull() || !file.file()->isValid() || file.file()->readOnly()) return 0;
        auto properties = file.file()->properties();
        TagLib::String name(key, TagLib::String::UTF8);
        if(value && *value) properties.replace(name, TagLib::StringList(TagLib::String(value, TagLib::String::UTF8)));
        else properties.erase(name);
        if(!file.file()->setProperties(properties).isEmpty()) return 0;
        return file.save() ? 1 : 0;
    } catch (...) { return 0; }
}

extern "C" int still_write_artwork(const char *path, const char *format, const unsigned char *bytes, size_t size, int png) {
    try {
        TagLib::ByteVector data(reinterpret_cast<const char *>(bytes), static_cast<unsigned int>(size));
        if(std::strcmp(format, "flac") == 0) {
            TagLib::FLAC::File file(path, false);
            if(!file.isValid() || file.readOnly()) return 0;
            // Replace front covers only; preserve booklet/back-cover images.
            auto pictures = file.pictureList();
            for(auto *picture : pictures) if(picture->type() == TagLib::FLAC::Picture::FrontCover) file.removePicture(picture);
            auto *picture = new TagLib::FLAC::Picture;
            picture->setType(TagLib::FLAC::Picture::FrontCover);
            picture->setMimeType(png ? "image/png" : "image/jpeg");
            picture->setData(data); file.addPicture(picture);
            return file.save();
        }
        if(std::strcmp(format, "mp3") == 0) {
            TagLib::MPEG::File file(path, false);
            if(!file.isValid() || file.readOnly()) return 0;
            auto *tag = file.ID3v2Tag(true);
            auto frames = tag->frameList("APIC");
            for(auto *frame : frames) {
                auto *picture = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(frame);
                if(picture && picture->type() == TagLib::ID3v2::AttachedPictureFrame::FrontCover) tag->removeFrame(frame);
            }
            auto *picture = new TagLib::ID3v2::AttachedPictureFrame;
            picture->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);
            picture->setMimeType(png ? "image/png" : "image/jpeg"); picture->setPicture(data); tag->addFrame(picture);
            const auto version = tag->header()->majorVersion() == 3 ? TagLib::ID3v2::v3 : TagLib::ID3v2::v4;
            return file.save(TagLib::MPEG::File::AllTags, TagLib::File::StripNone, version, TagLib::File::DoNotDuplicate);
        }
        if(std::strcmp(format, "m4a") == 0 || std::strcmp(format, "mp4") == 0) {
            TagLib::MP4::File file(path, false);
            if(!file.isValid() || file.readOnly()) return 0;
            TagLib::MP4::CoverArtList covers;
            covers.append(TagLib::MP4::CoverArt(png ? TagLib::MP4::CoverArt::PNG : TagLib::MP4::CoverArt::JPEG, data));
            file.tag()->setItem("covr", TagLib::MP4::Item(covers));
            return file.save();
        }
        return 0;
    } catch (...) { return 0; }
}
