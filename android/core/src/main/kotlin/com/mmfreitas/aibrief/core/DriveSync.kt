package com.mmfreitas.aibrief.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import java.util.UUID

/** The Google sign-in has expired or was revoked: sign in again. */
class DriveAuthError(message: String) : IOException(message)

/**
 * The synced copy of the collection: one JSON file ([SyncSnapshot]) in the user's Google Drive.
 *
 * Uses only the `drive.file` permission, which lets the app see the files it created and nothing
 * else in the Drive. The file is found by an app property rather than its name, so renaming or
 * moving it in Drive doesn't break syncing. Same file and rules in the macOS and Windows apps.
 *
 * @param accessToken returns a current OAuth access token for the signed-in Google account.
 */
class DriveFile(private val accessToken: suspend () -> String) : RemoteCollection {
    /** Finds the sync file. null when this account has none yet. */
    override suspend fun find(): String? {
        val q = "appProperties has { key='$PROPERTY' and value='1' } and trashed=false"
        val json = request("GET", "$API/files?spaces=drive&fields=files(id)&orderBy=createdTime&q=${encode(q)}")
        return json.obj("files")?.array?.firstOrNull()?.str("id")
    }

    override suspend fun read(id: String): SyncSnapshot {
        val body = requestText("GET", "$API/files/$id?alt=media")
        return try {
            BriefStore.json.decodeFromString(SyncSnapshot.serializer(), body)
        } catch (e: Exception) {
            throw FetchError.parse("the synced collection")
        }
    }

    /** Creates the sync file in the Drive's top folder and returns its ID. */
    override suspend fun create(snapshot: SyncSnapshot): String {
        val boundary = "refresher-${UUID.randomUUID()}"
        val metadata = """{"name":"$FILE_NAME","mimeType":"application/json","appProperties":{"$PROPERTY":"1"}}"""
        val body = "--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n" +
            "--$boundary\r\nContent-Type: application/json\r\n\r\n${encodeSnapshot(snapshot)}\r\n--$boundary--"
        val json = request("POST", "$UPLOAD/files?uploadType=multipart&fields=id", body, "multipart/related; boundary=$boundary")
        return json.str("id") ?: throw FetchError.parse("Google Drive's reply")
    }

    override suspend fun update(id: String, snapshot: SyncSnapshot) {
        request("PATCH", "$UPLOAD/files/$id?uploadType=media&fields=id", encodeSnapshot(snapshot), "application/json")
    }

    /** The signed-in account's email address, shown in Settings. */
    suspend fun email(): String? = request("GET", "$API/about?fields=user(emailAddress)").obj("user")?.str("emailAddress")

    private fun encodeSnapshot(s: SyncSnapshot) = BriefStore.json.encodeToString(SyncSnapshot.serializer(), s)

    private suspend fun request(method: String, url: String, body: String? = null, type: String? = null): JsonElement =
        lenient.parseToJsonElement(requestText(method, url, body, type).ifBlank { "{}" })

    private suspend fun requestText(method: String, url: String, body: String? = null, type: String? = null): String {
        val token = accessToken()
        return withContext(Dispatchers.IO) {
            val conn = URI(url).toURL().openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 30_000
                conn.readTimeout = 30_000
                // HttpURLConnection has no PATCH; Google accepts the override header.
                conn.requestMethod = if (method == "PATCH") "POST" else method
                if (method == "PATCH") conn.setRequestProperty("X-HTTP-Method-Override", "PATCH")
                conn.setRequestProperty("Authorization", "Bearer $token")
                if (body != null) {
                    conn.doOutput = true
                    conn.setRequestProperty("Content-Type", type)
                    conn.outputStream.use { it.write(body.toByteArray()) }
                }
                val code = conn.responseCode
                if (code == 401) throw DriveAuthError("Google sign-in expired")
                if (code !in 200..299) {
                    val detail = conn.errorStream?.use { it.readBytes().toString(Charsets.UTF_8) }.orEmpty()
                    throw FetchError("Google Drive returned HTTP $code${if (code == 403 && "insufficient" in detail.lowercase()) " (permission not granted)" else ""}")
                }
                conn.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
            } finally {
                conn.disconnect()
            }
        }
    }

    companion object {
        /** OAuth scope: only files this app created. */
        const val SCOPE = "https://www.googleapis.com/auth/drive.file"
        const val FILE_NAME = "AI-ML Refresher library.json"
        private const val PROPERTY = "refresherCollection"
        private const val API = "https://www.googleapis.com/drive/v3"
        private const val UPLOAD = "https://www.googleapis.com/upload/drive/v3"
        private val lenient = Json { ignoreUnknownKeys = true }
        private fun encode(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
    }
}

/** Where the synced copy lives. [DriveFile] in the apps; a fake in tests. */
interface RemoteCollection {
    suspend fun find(): String?
    suspend fun read(id: String): SyncSnapshot
    suspend fun create(snapshot: SyncSnapshot): String
    suspend fun update(id: String, snapshot: SyncSnapshot)
}

/** One sync: download the synced copy, merge it into the local collection, upload the result if it changed. */
class CollectionSyncer(private val store: BriefStore, private val remote: RemoteCollection) {
    /** @param changedLocally the local collection changed (reload the UI). */
    data class Outcome(val items: Int, val uploaded: Boolean, val changedLocally: Boolean)

    suspend fun sync(): Outcome {
        val id = remote.find()
        val theirs = id?.let { remote.read(it) } ?: SyncSnapshot()
        val before = normalized(SyncSnapshot(store.loadCollection(), store.loadDeleted()))
        val merged = store.mergeCollection(theirs)
        val upload = id == null || merged != normalized(theirs)
        if (upload) {
            if (id == null) remote.create(merged) else remote.update(id, merged)
        }
        return Outcome(merged.items.size, uploaded = upload, changedLocally = merged != before)
    }

    private fun normalized(s: SyncSnapshot) = CollectionSync.merge(s, SyncSnapshot())
}
