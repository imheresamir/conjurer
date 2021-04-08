--
-- PostgreSQL database dump
--

-- Dumped from database version 10.15 (Debian 10.15-1.pgdg90+1)
-- Dumped by pg_dump version 10.15 (Debian 10.15-1.pgdg90+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: DATABASE postgres; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE postgres IS 'default administrative connection database';


--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: policy_log_kind; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.policy_log_kind AS ENUM (
    'roles',
    'role_memberships',
    'resources',
    'permissions',
    'annotations'
);


ALTER TYPE public.policy_log_kind OWNER TO postgres;

--
-- Name: policy_log_op; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.policy_log_op AS ENUM (
    'INSERT',
    'DELETE',
    'UPDATE'
);


ALTER TYPE public.policy_log_op OWNER TO postgres;

--
-- Name: policy_log_record; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.policy_log_record AS (
	policy_id text,
	version integer,
	operation public.policy_log_op,
	kind public.policy_log_kind,
	subject public.hstore
);


ALTER TYPE public.policy_log_record OWNER TO postgres;

--
-- Name: role_graph_edge; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.role_graph_edge AS (
	parent text,
	child text
);


ALTER TYPE public.role_graph_edge OWNER TO postgres;

--
-- Name: account(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.account(id text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT CASE 
       WHEN split_part($1, ':', 1) = '' THEN NULL 
      ELSE split_part($1, ':', 1)
    END
    $_$;


ALTER FUNCTION public.account(id text) OWNER TO postgres;

--
-- Name: kind(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kind(id text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT CASE 
       WHEN split_part($1, ':', 2) = '' THEN NULL 
      ELSE split_part($1, ':', 2)
    END
    $_$;


ALTER FUNCTION public.kind(id text) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: resources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resources (
    resource_id text NOT NULL,
    owner_id text NOT NULL,
    created_at timestamp without time zone DEFAULT transaction_timestamp() NOT NULL,
    policy_id text,
    CONSTRAINT has_account CHECK ((public.account(resource_id) IS NOT NULL)),
    CONSTRAINT has_kind CHECK ((public.kind(resource_id) IS NOT NULL)),
    CONSTRAINT verify_policy_kind CHECK ((public.kind(policy_id) = 'policy'::text))
);


ALTER TABLE public.resources OWNER TO postgres;

--
-- Name: account(public.resources); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.account(record public.resources) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
        SELECT account(record.resource_id)
        $$;


ALTER FUNCTION public.account(record public.resources) OWNER TO postgres;

--
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    role_id text NOT NULL,
    created_at timestamp without time zone DEFAULT transaction_timestamp() NOT NULL,
    policy_id text,
    CONSTRAINT has_account CHECK ((public.account(role_id) IS NOT NULL)),
    CONSTRAINT has_kind CHECK ((public.kind(role_id) IS NOT NULL)),
    CONSTRAINT verify_policy_kind CHECK ((public.kind(policy_id) = 'policy'::text))
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- Name: account(public.roles); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.account(record public.roles) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
        SELECT account(record.role_id)
        $$;


ALTER FUNCTION public.account(record public.roles) OWNER TO postgres;

--
-- Name: all_roles(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.all_roles(role_id text) RETURNS TABLE(role_id text, admin_option boolean)
    LANGUAGE sql STABLE STRICT ROWS 2376
    AS $_$
          WITH RECURSIVE m(role_id, admin_option) AS (
            SELECT $1, 't'::boolean
              UNION
            SELECT ms.role_id, ms.admin_option FROM role_memberships ms, m
              WHERE member_id = m.role_id
          ) SELECT role_id, bool_or(admin_option) FROM m GROUP BY role_id
        $_$;


ALTER FUNCTION public.all_roles(role_id text) OWNER TO postgres;

--
-- Name: annotation_update_textsearch(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.annotation_update_textsearch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
        BEGIN
          IF TG_OP IN ('INSERT', 'UPDATE') THEN
          UPDATE resources_textsearch rts
            SET textsearch = (
              SELECT r.tsvector FROM resources r
              WHERE r.resource_id = rts.resource_id
            ) WHERE resource_id = NEW.resource_id;
          END IF;
          
          IF TG_OP IN ('UPDATE', 'DELETE') THEN
            BEGIN
              UPDATE resources_textsearch rts
              SET textsearch = (
                SELECT r.tsvector FROM resources r
                WHERE r.resource_id = rts.resource_id
              ) WHERE resource_id = OLD.resource_id;
            EXCEPTION WHEN foreign_key_violation THEN
              /*
              It's possible when an annotation is deleted that the entire resource
              has been deleted. When this is the case, attempting to update the
              search text will raise a foreign key violation on the missing
              resource_id. 
              */
              RAISE WARNING 'Cannot update search text for % because it no longer exists', OLD.resource_id;
              RETURN NULL;
            END;
          END IF;

          RETURN NULL;
        END
        $$;


ALTER FUNCTION public.annotation_update_textsearch() OWNER TO postgres;

--
-- Name: policy_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.policy_versions (
    resource_id text NOT NULL,
    role_id text NOT NULL,
    version integer NOT NULL,
    created_at timestamp with time zone DEFAULT transaction_timestamp() NOT NULL,
    policy_text text NOT NULL,
    policy_sha256 text NOT NULL,
    finished_at timestamp with time zone,
    client_ip text,
    CONSTRAINT created_before_finish CHECK ((created_at <= finished_at))
);


ALTER TABLE public.policy_versions OWNER TO postgres;

--
-- Name: current_policy_version(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.current_policy_version() RETURNS SETOF public.policy_versions
    LANGUAGE sql STABLE
    SET search_path TO '$user', 'public'
    AS $$
          SELECT * FROM policy_versions WHERE finished_at IS NULL $$;


ALTER FUNCTION public.current_policy_version() OWNER TO postgres;

--
-- Name: delete_role_membership_of_owner(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_role_membership_of_owner(role_id text, owner_id text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
      DECLARE
        row_count int;
      BEGIN
        DELETE FROM role_memberships rm
          WHERE rm.role_id = $1 AND
            member_id = $2 AND
            ownership = true;
        GET DIAGNOSTICS row_count = ROW_COUNT;
        RETURN row_count;
      END
      $_$;


ALTER FUNCTION public.delete_role_membership_of_owner(role_id text, owner_id text) OWNER TO postgres;

--
-- Name: delete_role_membership_of_owner_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_role_membership_of_owner_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        PERFORM delete_role_membership_of_owner(OLD.resource_id, OLD.owner_id);

        RETURN OLD;
      END
      $$;


ALTER FUNCTION public.delete_role_membership_of_owner_trigger() OWNER TO postgres;

--
-- Name: grant_role_membership_to_owner(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.grant_role_membership_to_owner(role_id text, owner_id text) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
      DECLARE
        rolsource_role roles%rowtype;
        existing_grant role_memberships%rowtype;
      BEGIN
        SELECT * INTO rolsource_role FROM roles WHERE roles.role_id = $1;
        IF FOUND THEN
          SELECT * INTO existing_grant FROM role_memberships rm WHERE rm.role_id = $1 AND rm.member_id = $2 AND rm.admin_option = true AND rm.ownership = true;
          IF NOT FOUND THEN
            INSERT INTO role_memberships ( role_id, member_id, admin_option, ownership )
              VALUES ( $1, $2, true, true );
            RETURN 1;
          END IF;
        END IF;
        RETURN 0;
      END
      $_$;


ALTER FUNCTION public.grant_role_membership_to_owner(role_id text, owner_id text) OWNER TO postgres;

--
-- Name: grant_role_membership_to_owner_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.grant_role_membership_to_owner_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        PERFORM grant_role_membership_to_owner(NEW.resource_id, NEW.owner_id);
        RETURN NEW;
      END
      $$;


ALTER FUNCTION public.grant_role_membership_to_owner_trigger() OWNER TO postgres;

--
-- Name: identifier(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.identifier(id text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT SUBSTRING($1 from '[^:]+:[^:]+:(.*)');
    $_$;


ALTER FUNCTION public.identifier(id text) OWNER TO postgres;

--
-- Name: identifier(public.resources); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.identifier(record public.resources) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
      SELECT identifier(record.resource_id)
      $$;


ALTER FUNCTION public.identifier(record public.resources) OWNER TO postgres;

--
-- Name: identifier(public.roles); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.identifier(record public.roles) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
      SELECT identifier(record.role_id)
      $$;


ALTER FUNCTION public.identifier(record public.roles) OWNER TO postgres;

--
-- Name: is_resource_visible(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_resource_visible(resource_id text, role_id text) RETURNS boolean
    LANGUAGE sql STABLE STRICT
    AS $_$
        WITH RECURSIVE search(role_id) AS (
          -- We expand transitively back from the set of roles that the
          -- resource is visible to instead of relying on all_roles().
          -- This has the advantage of not being sensitive to the size of the
          -- role graph of the argument and hence offers stable performance
          -- even when a powerful role is tested, at the expense of slightly
          -- worse performance of a failed check for a locked-down role.
          -- This way all checks take ~ 1 ms regardless of the role.
          SELECT owner_id FROM resources WHERE resource_id = $1
            UNION
          SELECT role_id FROM permissions WHERE resource_id = $1
            UNION
          SELECT m.member_id
            FROM role_memberships m NATURAL JOIN search s
        )
        SELECT COUNT(*) > 0 FROM (
          SELECT true FROM search
            WHERE role_id = $2
            LIMIT 1 -- early cutoff: abort search if found
        ) AS found
      $_$;


ALTER FUNCTION public.is_resource_visible(resource_id text, role_id text) OWNER TO postgres;

--
-- Name: is_role_allowed_to(text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_role_allowed_to(role_id text, privilege text, resource_id text) RETURNS boolean
    LANGUAGE sql STABLE STRICT
    AS $_$
        WITH 
          all_roles AS (SELECT role_id FROM all_roles($1))
        SELECT COUNT(*) > 0 FROM (
          SELECT 1 FROM all_roles, resources 
          WHERE owner_id = role_id
            AND resources.resource_id = $3
        UNION
          SELECT 1 FROM ( all_roles JOIN permissions USING ( role_id ) ) JOIN resources USING ( resource_id )
          WHERE privilege = $2
            AND resources.resource_id = $3
        ) AS _
      $_$;


ALTER FUNCTION public.is_role_allowed_to(role_id text, privilege text, resource_id text) OWNER TO postgres;

--
-- Name: is_role_ancestor_of(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_role_ancestor_of(role_id text, other_id text) RETURNS boolean
    LANGUAGE sql STABLE STRICT
    AS $_$
        SELECT COUNT(*) > 0 FROM (
          WITH RECURSIVE m(id) AS (
            SELECT $2
            UNION ALL
            SELECT role_id FROM role_memberships rm, m WHERE member_id = id
          )
          SELECT true FROM m WHERE id = $1 LIMIT 1
        )_
      $_$;


ALTER FUNCTION public.is_role_ancestor_of(role_id text, other_id text) OWNER TO postgres;

--
-- Name: kind(public.resources); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kind(record public.resources) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
        SELECT kind(record.resource_id)
        $$;


ALTER FUNCTION public.kind(record public.resources) OWNER TO postgres;

--
-- Name: kind(public.roles); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.kind(record public.roles) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
        SELECT kind(record.role_id)
        $$;


ALTER FUNCTION public.kind(record public.roles) OWNER TO postgres;

--
-- Name: policy_log_annotations(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_log_annotations() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
          DECLARE
            subject annotations;
            current policy_versions;
            skip boolean;
          BEGIN
            IF (TG_OP = 'DELETE') THEN
              subject := OLD;
            ELSE
              subject := NEW;
            END IF;

            BEGIN
                skip := current_setting('conjur.skip_insert_policy_log_trigger');
            EXCEPTION WHEN OTHERS THEN
                skip := false;
            END;

            IF skip THEN
              RETURN subject;
            END IF;

            current = current_policy_version();
            IF current.resource_id = subject.policy_id THEN
              INSERT INTO policy_log(
                policy_id, version,
                operation, kind,
                subject)
              SELECT
                (policy_log_record(
                    'annotations',
                    ARRAY['resource_id','name'],
                    hstore(subject),
                    current.resource_id,
                    current.version,
                    TG_OP
                  )).*;
            ELSE
              RAISE WARNING 'modifying data outside of policy load: %', subject.policy_id;
            END IF;
            RETURN subject;
          END;
        $$;


ALTER FUNCTION public.policy_log_annotations() OWNER TO postgres;

--
-- Name: policy_log_permissions(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_log_permissions() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
          DECLARE
            subject permissions;
            current policy_versions;
            skip boolean;
          BEGIN
            IF (TG_OP = 'DELETE') THEN
              subject := OLD;
            ELSE
              subject := NEW;
            END IF;

            BEGIN
                skip := current_setting('conjur.skip_insert_policy_log_trigger');
            EXCEPTION WHEN OTHERS THEN
                skip := false;
            END;

            IF skip THEN
              RETURN subject;
            END IF;

            current = current_policy_version();
            IF current.resource_id = subject.policy_id THEN
              INSERT INTO policy_log(
                policy_id, version,
                operation, kind,
                subject)
              SELECT
                (policy_log_record(
                    'permissions',
                    ARRAY['privilege','resource_id','role_id'],
                    hstore(subject),
                    current.resource_id,
                    current.version,
                    TG_OP
                  )).*;
            ELSE
              RAISE WARNING 'modifying data outside of policy load: %', subject.policy_id;
            END IF;
            RETURN subject;
          END;
        $$;


ALTER FUNCTION public.policy_log_permissions() OWNER TO postgres;

--
-- Name: policy_log_record(text, text[], public.hstore, text, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_log_record(table_name text, pkey_cols text[], subject public.hstore, policy_id text, policy_version integer, operation text) RETURNS public.policy_log_record
    LANGUAGE plpgsql
    AS $$
      BEGIN
        return (
          policy_id,
          policy_version,
          operation::policy_log_op,
          table_name::policy_log_kind,
          slice(subject, pkey_cols)
          );
      END;
      $$;


ALTER FUNCTION public.policy_log_record(table_name text, pkey_cols text[], subject public.hstore, policy_id text, policy_version integer, operation text) OWNER TO postgres;

--
-- Name: policy_log_resources(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_log_resources() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
          DECLARE
            subject resources;
            current policy_versions;
            skip boolean;
          BEGIN
            IF (TG_OP = 'DELETE') THEN
              subject := OLD;
            ELSE
              subject := NEW;
            END IF;

            BEGIN
                skip := current_setting('conjur.skip_insert_policy_log_trigger');
            EXCEPTION WHEN OTHERS THEN
                skip := false;
            END;

            IF skip THEN
              RETURN subject;
            END IF;

            current = current_policy_version();
            IF current.resource_id = subject.policy_id THEN
              INSERT INTO policy_log(
                policy_id, version,
                operation, kind,
                subject)
              SELECT
                (policy_log_record(
                    'resources',
                    ARRAY['resource_id'],
                    hstore(subject),
                    current.resource_id,
                    current.version,
                    TG_OP
                  )).*;
            ELSE
              RAISE WARNING 'modifying data outside of policy load: %', subject.policy_id;
            END IF;
            RETURN subject;
          END;
        $$;


ALTER FUNCTION public.policy_log_resources() OWNER TO postgres;

--
-- Name: policy_log_role_memberships(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_log_role_memberships() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
          DECLARE
            subject role_memberships;
            current policy_versions;
            skip boolean;
          BEGIN
            IF (TG_OP = 'DELETE') THEN
              subject := OLD;
            ELSE
              subject := NEW;
            END IF;

            BEGIN
                skip := current_setting('conjur.skip_insert_policy_log_trigger');
            EXCEPTION WHEN OTHERS THEN
                skip := false;
            END;

            IF skip THEN
              RETURN subject;
            END IF;

            current = current_policy_version();
            IF current.resource_id = subject.policy_id THEN
              INSERT INTO policy_log(
                policy_id, version,
                operation, kind,
                subject)
              SELECT
                (policy_log_record(
                    'role_memberships',
                    ARRAY['role_id','member_id','ownership'],
                    hstore(subject),
                    current.resource_id,
                    current.version,
                    TG_OP
                  )).*;
            ELSE
              RAISE WARNING 'modifying data outside of policy load: %', subject.policy_id;
            END IF;
            RETURN subject;
          END;
        $$;


ALTER FUNCTION public.policy_log_role_memberships() OWNER TO postgres;

--
-- Name: policy_log_roles(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_log_roles() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
          DECLARE
            subject roles;
            current policy_versions;
            skip boolean;
          BEGIN
            IF (TG_OP = 'DELETE') THEN
              subject := OLD;
            ELSE
              subject := NEW;
            END IF;

            BEGIN
                skip := current_setting('conjur.skip_insert_policy_log_trigger');
            EXCEPTION WHEN OTHERS THEN
                skip := false;
            END;

            IF skip THEN
              RETURN subject;
            END IF;

            current = current_policy_version();
            IF current.resource_id = subject.policy_id THEN
              INSERT INTO policy_log(
                policy_id, version,
                operation, kind,
                subject)
              SELECT
                (policy_log_record(
                    'roles',
                    ARRAY['role_id'],
                    hstore(subject),
                    current.resource_id,
                    current.version,
                    TG_OP
                  )).*;
            ELSE
              RAISE WARNING 'modifying data outside of policy load: %', subject.policy_id;
            END IF;
            RETURN subject;
          END;
        $$;


ALTER FUNCTION public.policy_log_roles() OWNER TO postgres;

--
-- Name: policy_versions_finish(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_versions_finish() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        BEGIN
          UPDATE policy_versions pv
            SET finished_at = clock_timestamp()
            WHERE finished_at IS NULL;
          RETURN new;
        END;
      $$;


ALTER FUNCTION public.policy_versions_finish() OWNER TO postgres;

--
-- Name: policy_versions_next_version(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.policy_versions_next_version() RETURNS trigger
    LANGUAGE plpgsql STABLE STRICT
    AS $$
        DECLARE
          next_version integer;
        BEGIN
          SELECT coalesce(max(version), 0) + 1 INTO next_version
            FROM policy_versions 
            WHERE resource_id = NEW.resource_id;

          NEW.version = next_version;
          RETURN NEW;
        END
        $$;


ALTER FUNCTION public.policy_versions_next_version() OWNER TO postgres;

--
-- Name: resource_update_textsearch(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.resource_update_textsearch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO '$user', 'public'
    AS $$
        BEGIN
          IF TG_OP = 'INSERT' THEN
            INSERT INTO resources_textsearch
            VALUES (NEW.resource_id, tsvector(NEW));
          ELSE
            UPDATE resources_textsearch
            SET textsearch = tsvector(NEW)
            WHERE resource_id = NEW.resource_id;
          END IF;

          RETURN NULL;
        END
        $$;


ALTER FUNCTION public.resource_update_textsearch() OWNER TO postgres;

--
-- Name: role_graph(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.role_graph(start_role text) RETURNS SETOF public.role_graph_edge
    LANGUAGE sql STABLE
    AS $$

        WITH RECURSIVE 
        -- Ancestor tree
        up AS (
          (SELECT role_id, member_id FROM role_memberships LIMIT 0)
          UNION ALL
            SELECT start_role, NULL

          UNION

          SELECT rm.role_id, rm.member_id FROM role_memberships rm, up
          WHERE up.role_id = rm.member_id
        ),

        -- Descendent tree
        down AS (
            (SELECT role_id, member_id FROM role_memberships LIMIT 0)
          UNION ALL
            SELECT NULL, start_role

          UNION

          SELECT rm.role_id, rm.member_id FROM role_memberships rm, down
          WHERE down.member_id = rm.role_id
        ),

        total AS (
          SELECT * FROM up
          UNION

          -- add immediate children of the ancestors
          -- (they can be fetched anyway through role_members method)
          SELECT rm.role_id, rm.member_id FROM role_memberships rm, up WHERE rm.role_id = up.role_id

          UNION
          SELECT * FROM down
        )

        SELECT * FROM total WHERE role_id IS NOT NULL AND member_id IS NOT NULL
        UNION
        SELECT role_id, member_id FROM role_memberships WHERE start_role IS NULL

      $$;


ALTER FUNCTION public.role_graph(start_role text) OWNER TO postgres;

--
-- Name: FUNCTION role_graph(start_role text); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.role_graph(start_role text) IS 'if role is not null, returns role_memberships culled to include only the two trees rooted at given role, plus the skin of the up tree; otherwise returns all of role_memberships';


--
-- Name: roles_that_can(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.roles_that_can(permission text, resource_id text) RETURNS SETOF public.roles
    LANGUAGE sql STABLE STRICT ROWS 10
    AS $_$
          WITH RECURSIVE allowed_roles(role_id) AS (
            SELECT role_id FROM permissions
              WHERE privilege = $1
                AND resource_id = $2
            UNION SELECT owner_id FROM resources
                WHERE resources.resource_id = $2
            UNION SELECT member_id AS role_id FROM role_memberships ms NATURAL JOIN allowed_roles
            ) SELECT DISTINCT r.* FROM roles r NATURAL JOIN allowed_roles;
        $_$;


ALTER FUNCTION public.roles_that_can(permission text, resource_id text) OWNER TO postgres;

--
-- Name: secrets_next_version(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.secrets_next_version() RETURNS trigger
    LANGUAGE plpgsql STABLE STRICT
    AS $$
        DECLARE
          next_version integer;
        BEGIN
          SELECT coalesce(max(version), 0) + 1 INTO next_version
            FROM secrets 
            WHERE resource_id = NEW.resource_id;

          NEW.version = next_version;
          RETURN NEW;
        END
        $$;


ALTER FUNCTION public.secrets_next_version() OWNER TO postgres;

--
-- Name: tsvector(public.resources); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.tsvector(resource public.resources) RETURNS tsvector
    LANGUAGE sql
    AS $$
        WITH annotations AS (
          SELECT name, value FROM annotations
          WHERE resource_id = resource.resource_id
        )
        SELECT
        -- id and name are A

        -- Translate chars that are not considered word separators by parser. Note that Conjur v3's /authz
        -- did not include a period here. It has been added for Conjur OSS.
        -- Note: although ids are not english, use english dict so that searching is simpler, if less strict
        setweight(to_tsvector('pg_catalog.english', translate(identifier(resource.resource_id), './-', '   ')), 'A') ||

        setweight(to_tsvector('pg_catalog.english',
          coalesce((SELECT value FROM annotations WHERE name = 'name'), '')
        ), 'A') ||

        -- other annotations are B
        setweight(to_tsvector('pg_catalog.english',
          (SELECT coalesce(string_agg(value, ' :: '), '') FROM annotations WHERE name <> 'name')
        ), 'B') ||

        -- kind is C
        setweight(to_tsvector('pg_catalog.english', kind(resource.resource_id)), 'C')
        $$;


ALTER FUNCTION public.tsvector(resource public.resources) OWNER TO postgres;

--
-- Name: update_role_membership_of_owner_trigger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_role_membership_of_owner_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF OLD.owner_id != NEW.owner_id THEN
          PERFORM delete_role_membership_of_owner(OLD.resource_id, OLD.owner_id);
          PERFORM grant_role_membership_to_owner(OLD.resource_id, NEW.owner_id);
        END IF;
        RETURN NEW;
      END
      $$;


ALTER FUNCTION public.update_role_membership_of_owner_trigger() OWNER TO postgres;

--
-- Name: visible_resources(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.visible_resources(role_id text) RETURNS SETOF public.resources
    LANGUAGE sql STABLE STRICT
    AS $$
        WITH
          all_roles AS (SELECT * FROM all_roles(role_id)),
          permitted AS (
            SELECT DISTINCT resource_id FROM permissions NATURAL JOIN all_roles
          )
        SELECT *
          FROM resources
          WHERE
            -- resource is visible if there are any permissions or ownerships held on it
            owner_id IN (SELECT role_id FROM all_roles)
            OR resource_id IN (SELECT resource_id FROM permitted)
      $$;


ALTER FUNCTION public.visible_resources(role_id text) OWNER TO postgres;

--
-- Name: annotations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.annotations (
    resource_id text NOT NULL,
    name text NOT NULL,
    value text NOT NULL,
    policy_id text,
    CONSTRAINT verify_policy_kind CHECK ((public.kind(policy_id) = 'policy'::text))
);


ALTER TABLE public.annotations OWNER TO postgres;

--
-- Name: authenticator_configs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.authenticator_configs (
    id integer NOT NULL,
    resource_id text NOT NULL,
    enabled boolean DEFAULT false NOT NULL
);


ALTER TABLE public.authenticator_configs OWNER TO postgres;

--
-- Name: authenticator_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.authenticator_configs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.authenticator_configs_id_seq OWNER TO postgres;

--
-- Name: authenticator_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.authenticator_configs_id_seq OWNED BY public.authenticator_configs.id;


--
-- Name: credentials; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.credentials (
    role_id text NOT NULL,
    client_id text,
    api_key bytea,
    encrypted_hash bytea,
    expiration timestamp without time zone,
    restricted_to cidr[] DEFAULT '{}'::cidr[] NOT NULL
);


ALTER TABLE public.credentials OWNER TO postgres;

--
-- Name: host_factory_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.host_factory_tokens (
    token_sha256 character varying(64) NOT NULL,
    token bytea NOT NULL,
    resource_id text NOT NULL,
    cidr cidr[] DEFAULT '{}'::cidr[] NOT NULL,
    expiration timestamp without time zone
);


ALTER TABLE public.host_factory_tokens OWNER TO postgres;

--
-- Name: permissions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.permissions (
    privilege text NOT NULL,
    resource_id text NOT NULL,
    role_id text NOT NULL,
    policy_id text,
    CONSTRAINT verify_policy_kind CHECK ((public.kind(policy_id) = 'policy'::text))
);


ALTER TABLE public.permissions OWNER TO postgres;

--
-- Name: policy_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.policy_log (
    policy_id text NOT NULL,
    version integer NOT NULL,
    operation public.policy_log_op NOT NULL,
    kind public.policy_log_kind NOT NULL,
    subject public.hstore NOT NULL,
    at timestamp with time zone DEFAULT clock_timestamp() NOT NULL
);


ALTER TABLE public.policy_log OWNER TO postgres;

--
-- Name: resources_textsearch; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resources_textsearch (
    resource_id text NOT NULL,
    textsearch tsvector
);


ALTER TABLE public.resources_textsearch OWNER TO postgres;

--
-- Name: role_memberships; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.role_memberships (
    role_id text NOT NULL,
    member_id text NOT NULL,
    admin_option boolean DEFAULT false NOT NULL,
    ownership boolean DEFAULT false NOT NULL,
    policy_id text,
    CONSTRAINT verify_policy_kind CHECK ((public.kind(policy_id) = 'policy'::text))
);


ALTER TABLE public.role_memberships OWNER TO postgres;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schema_migrations (
    filename text NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO postgres;

--
-- Name: secrets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.secrets (
    resource_id text NOT NULL,
    version integer NOT NULL,
    value bytea NOT NULL,
    expires_at timestamp without time zone
);


ALTER TABLE public.secrets OWNER TO postgres;

--
-- Name: slosilo_keystore; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.slosilo_keystore (
    id text NOT NULL,
    key bytea NOT NULL,
    fingerprint text NOT NULL
);


ALTER TABLE public.slosilo_keystore OWNER TO postgres;

--
-- Name: authenticator_configs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_configs ALTER COLUMN id SET DEFAULT nextval('public.authenticator_configs_id_seq'::regclass);


--
-- Data for Name: annotations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.annotations (resource_id, name, value, policy_id) FROM stdin;
\.


--
-- Data for Name: authenticator_configs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.authenticator_configs (id, resource_id, enabled) FROM stdin;
\.


--
-- Data for Name: credentials; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.credentials (role_id, client_id, api_key, encrypted_hash, expiration, restricted_to) FROM stdin;
myConjurAccount:user:admin	\N	\\x479dae77ec3b3b3cf5ac5a424faafbb71c66ad85e110158ad841218fbe638aa38f9c6b5213343c88712f774304fca34b9af5e3ed3181b4d3b763b0088a4d237d2aeefa3a6dcdd0ff35ad2938ee19c5406e6cf9	\N	\N	{}
myConjurAccount:user:Dave@BotApp	\N	\\x477b97f97cc74bf8ca4d6a9ee1a39b856cf2b670dc44ff943ae032f0f548215bbef7db9360d6009eb0be89bf8c1a2fdbc8c5d430c7604de0b1ffbbf3d614701e3177548b3b360dc7c2b2eb73ae60fe0655	\N	\N	{}
myConjurAccount:host:BotApp/myDemoApp	\N	\\x473be137b8ad7a56db65b7e1f29f5db2a0590a41797c950410a46d6a55e6f5ea3bb4bdb0bf5d75dc2b098031d805b334e8a55132b2a28e289c19152cff73d2d87ef29c37078655af079b83f99bb8aba6ca	\N	\N	{}
\.


--
-- Data for Name: host_factory_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.host_factory_tokens (token_sha256, token, resource_id, cidr, expiration) FROM stdin;
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.permissions (privilege, resource_id, role_id, policy_id) FROM stdin;
read	myConjurAccount:variable:BotApp/secretVar	myConjurAccount:user:Dave@BotApp	myConjurAccount:policy:root
update	myConjurAccount:variable:BotApp/secretVar	myConjurAccount:user:Dave@BotApp	myConjurAccount:policy:root
execute	myConjurAccount:variable:BotApp/secretVar	myConjurAccount:user:Dave@BotApp	myConjurAccount:policy:root
read	myConjurAccount:variable:BotApp/secretVar	myConjurAccount:host:BotApp/myDemoApp	myConjurAccount:policy:root
execute	myConjurAccount:variable:BotApp/secretVar	myConjurAccount:host:BotApp/myDemoApp	myConjurAccount:policy:root
\.


--
-- Data for Name: policy_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.policy_log (policy_id, version, operation, kind, subject, at) FROM stdin;
myConjurAccount:policy:root	1	INSERT	roles	"role_id"=>"myConjurAccount:policy:BotApp"	2021-04-06 05:37:00.6132+00
myConjurAccount:policy:root	1	INSERT	roles	"role_id"=>"myConjurAccount:user:Dave@BotApp"	2021-04-06 05:37:00.613538+00
myConjurAccount:policy:root	1	INSERT	roles	"role_id"=>"myConjurAccount:host:BotApp/myDemoApp"	2021-04-06 05:37:00.613618+00
myConjurAccount:policy:root	1	INSERT	role_memberships	"role_id"=>"myConjurAccount:policy:BotApp", "member_id"=>"myConjurAccount:user:admin", "ownership"=>"t"	2021-04-06 05:37:00.622757+00
myConjurAccount:policy:root	1	INSERT	role_memberships	"role_id"=>"myConjurAccount:user:Dave@BotApp", "member_id"=>"myConjurAccount:policy:BotApp", "ownership"=>"t"	2021-04-06 05:37:00.622863+00
myConjurAccount:policy:root	1	INSERT	role_memberships	"role_id"=>"myConjurAccount:host:BotApp/myDemoApp", "member_id"=>"myConjurAccount:policy:BotApp", "ownership"=>"t"	2021-04-06 05:37:00.622944+00
myConjurAccount:policy:root	1	INSERT	resources	"resource_id"=>"myConjurAccount:policy:BotApp"	2021-04-06 05:37:00.639346+00
myConjurAccount:policy:root	1	INSERT	resources	"resource_id"=>"myConjurAccount:user:Dave@BotApp"	2021-04-06 05:37:00.639441+00
myConjurAccount:policy:root	1	INSERT	resources	"resource_id"=>"myConjurAccount:host:BotApp/myDemoApp"	2021-04-06 05:37:00.639546+00
myConjurAccount:policy:root	1	INSERT	resources	"resource_id"=>"myConjurAccount:variable:BotApp/secretVar"	2021-04-06 05:37:00.639628+00
myConjurAccount:policy:root	1	INSERT	permissions	"role_id"=>"myConjurAccount:user:Dave@BotApp", "privilege"=>"read", "resource_id"=>"myConjurAccount:variable:BotApp/secretVar"	2021-04-06 05:37:00.649363+00
myConjurAccount:policy:root	1	INSERT	permissions	"role_id"=>"myConjurAccount:user:Dave@BotApp", "privilege"=>"update", "resource_id"=>"myConjurAccount:variable:BotApp/secretVar"	2021-04-06 05:37:00.649457+00
myConjurAccount:policy:root	1	INSERT	permissions	"role_id"=>"myConjurAccount:user:Dave@BotApp", "privilege"=>"execute", "resource_id"=>"myConjurAccount:variable:BotApp/secretVar"	2021-04-06 05:37:00.649562+00
myConjurAccount:policy:root	1	INSERT	permissions	"role_id"=>"myConjurAccount:host:BotApp/myDemoApp", "privilege"=>"read", "resource_id"=>"myConjurAccount:variable:BotApp/secretVar"	2021-04-06 05:37:00.649641+00
myConjurAccount:policy:root	1	INSERT	permissions	"role_id"=>"myConjurAccount:host:BotApp/myDemoApp", "privilege"=>"execute", "resource_id"=>"myConjurAccount:variable:BotApp/secretVar"	2021-04-06 05:37:00.649719+00
myConjurAccount:policy:root	1	UPDATE	roles	"role_id"=>"myConjurAccount:user:Dave@BotApp"	2021-04-06 05:37:00.666172+00
myConjurAccount:policy:root	1	UPDATE	roles	"role_id"=>"myConjurAccount:host:BotApp/myDemoApp"	2021-04-06 05:37:00.669507+00
\.


--
-- Data for Name: policy_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.policy_versions (resource_id, role_id, version, created_at, policy_text, policy_sha256, finished_at, client_ip) FROM stdin;
myConjurAccount:policy:root	myConjurAccount:user:admin	1	2021-04-06 05:37:00.219629+00	- !policy\n  id: BotApp\n  body:\n    # Define a human user, a non-human identity that represents an application, and a secret\n  - !user Dave\n  - !host myDemoApp\n  - !variable secretVar\n  - !permit\n    # Give permissions to the human user to update the secret and fetch the secret.\n    role: !user Dave\n    privileges: [read, update, execute]\n    resource: !variable secretVar\n  - !permit\n    # Give permissions to the non-human identity to fetch the secret.\n    role: !host myDemoApp\n    privileges: [read, execute]\n    resource: !variable secretVar\n	bc12f933b54e29e412088c29dd85c534770ed32f792f04195ba0efe9ac7087ae	2021-04-06 05:37:00.685153+00	172.19.0.6
\.


--
-- Data for Name: resources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resources (resource_id, owner_id, created_at, policy_id) FROM stdin;
!:webservice:accounts	!:!:root	2021-04-03 01:34:38.541824	\N
myConjurAccount:policy:root	myConjurAccount:user:admin	2021-04-06 05:37:00.219629	\N
myConjurAccount:policy:BotApp	myConjurAccount:user:admin	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
myConjurAccount:user:Dave@BotApp	myConjurAccount:policy:BotApp	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
myConjurAccount:host:BotApp/myDemoApp	myConjurAccount:policy:BotApp	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
myConjurAccount:variable:BotApp/secretVar	myConjurAccount:policy:BotApp	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
\.


--
-- Data for Name: resources_textsearch; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resources_textsearch (resource_id, textsearch) FROM stdin;
!:webservice:accounts	'account':1A 'webservic':2C
myConjurAccount:policy:root	'polici':2C 'root':1A
myConjurAccount:policy:BotApp	'botapp':1A 'polici':2C
myConjurAccount:user:Dave@BotApp	'botapp':2A 'dave':1A 'user':3C
myConjurAccount:host:BotApp/myDemoApp	'botapp':1A 'host':3C 'mydemoapp':2A
myConjurAccount:variable:BotApp/secretVar	'botapp':1A 'secretvar':2A 'variabl':3C
\.


--
-- Data for Name: role_memberships; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.role_memberships (role_id, member_id, admin_option, ownership, policy_id) FROM stdin;
myConjurAccount:policy:root	myConjurAccount:user:admin	t	t	\N
myConjurAccount:policy:BotApp	myConjurAccount:user:admin	t	t	myConjurAccount:policy:root
myConjurAccount:user:Dave@BotApp	myConjurAccount:policy:BotApp	t	t	myConjurAccount:policy:root
myConjurAccount:host:BotApp/myDemoApp	myConjurAccount:policy:BotApp	t	t	myConjurAccount:policy:root
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (role_id, created_at, policy_id) FROM stdin;
!:!:root	2021-04-03 01:34:38.52174	\N
myConjurAccount:user:admin	2021-04-03 01:34:38.555847	\N
myConjurAccount:policy:root	2021-04-06 05:37:00.219629	\N
myConjurAccount:policy:BotApp	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
myConjurAccount:user:Dave@BotApp	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
myConjurAccount:host:BotApp/myDemoApp	2021-04-06 05:37:00.219629	myConjurAccount:policy:root
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schema_migrations (filename) FROM stdin;
20121215032820_create_keystore.rb
20160628212347_create_roles.rb
20160628212349_create_resources.rb
20160628212358_create_role_memberships.rb
20160628212428_create_permissions.rb
20160628212433_create_annotations.rb
20160628222441_create_credentials.rb
20160630172059_create_secrets.rb
20160705141848_create_authz_functions.rb
20160801210433_create_id_functions.rb
20160815131453_create_policy_version.rb
20160815131521_add_policy_column.rb
20160906135444_create_owner_functions.rb
20170404125612_create_host_factories.rb
20170710163523_create_resources_textsearch.rb
20180410071554_current_policy.rb
20180410092453_policy_log.rb
20180422043957_resource_visibility.rb
20180508164825_add_expiration.rb
20180530162704_is_role_ancestor_of.rb
20180618161021_role_graph.rb
20180705192211_credentials_restricted_to_cidr.rb
20190307154241_change_permissions_primary_key.rb
20191112025200_create_authenticator_config.rb
20200605203735_add_policy_version_client_ip.rb
20200811181056_reset_fingerprint_column.rb
20201119122834_update_annotation_update_textsearch.rb
201808131137612_policy_log_trigger_bypass.rb
\.


--
-- Data for Name: secrets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.secrets (resource_id, version, value, expires_at) FROM stdin;
\.


--
-- Data for Name: slosilo_keystore; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.slosilo_keystore (id, key, fingerprint) FROM stdin;
authn:!	\\x472719566e4012a8acd1fac04e936ddcdedb123b3280007590aade3227b6dab1f45720c396126895c98df5ae5d9b96b6422f731b37655ff97b602926b05567e4e4ea549d73c9dc1607fcc6fe51459d4838e2eca46ab0029cb9fcc564c2f270c5a8683c4fc4c7a5d58f4f51ec26252090ddfdb57328f8444ea000e527d0053353a14dccea4fe1001a000bbc5054bf7b3994f4466b3e881007ffca073c0d01a02fe2060d02b3adc86814fb2debd86b273b52b2935caf13e0f6d859aad1952d01929c878986e09f9fe2807f2ce5ebbc80a9a1c7e8b991c090dc3b74bd4308af7a548dc13a202fc55c59ea68cfe9e576738bd8ca68d8c0bb65c25501a81666b9fa6ce135ddda76e73e9ee76f6428b060ec86fa12dc9a7deda597748deef402c0fc88a38a3f8e5b0659227db242c203f7b2c42300ed0ac30209c66702e3f4cad2a2d304a4af9cda0307c44f9e9f34b172dc9ff723de1eadd483c07d20796fa2ba00728397cae8d9031cdd0c506ef664446b78ae5c2d9bf40c7490fbb1311cc5176c815009a6e72e749b08c601e6b41ad0e8e29f62785027971b785a2915dd5cfc39ef3e61aeb1a7b6354ff96c94085f62a6e2f868483476428b05821446ae7e2360d443a51595b757cad5823b1c70975248ef4bcebdd50351356d45d02610af20ea18eaf3d0e1d7a1f526bf4db3bfa0c6092d88581a35e259f27fecb1af93fd1168956839ef3b118fd71c2d4cddb505961702b58a55db6865c02daed502ec95560272ec89966b5b631d021c258c46fc1bfc0e3234b186a3887d857b402bd0899f55e4befd318dd08b3b330ad7fe764806b55b9b8b05a609bfbebe2c380473587a66998ed0ba5773c57f0d220fa480a16a79161670703a4721f0518439af76a99bc7d91d8caf0c5950ce042b84457ff9187ee0be1ef4d388e4c6b2f74be520285a428f9ec3852836d6e94389480dbed5a6115b676b92aad8bf5ae631228f989fa7c3e76d636133a2a7ae73a1a53c511b30a7dde830ab786c041012273c8d70ef4e8a960a58c871753cb69eead4452fa358aef4503261fca589a1277737bfd6a0c43e635d3cfb3d8709fc7a70f47ceff812687a03b8135fcb11b551a9391312a807bb1a9f3a89c9ca2f00f6b013a7d4a77708a03db450862182dd2731e170e49bdd89e6f0753189da05e8f049edff88ad1226620e388ba8172723adcbd8aea43c9aa7a7eb94645f42599137f8a1b9746840f716e25b94b7a3da4332eb0839aa7a020a5e64de99120d3783d818aa21a9dfeeaf3e5861195f1f45145c49a0ae6c5e67563d207a41939bf9ed6aa08a5de33419392e984e24251f84633d2950b8f94feeba5780964f286ceecb26712246b54e7828435dd66cd3759212386f43a53fb527f047b29a68cf3be207ed8e4166f9111dcacc4b597dc4c04667961e4e984d005f686bd41887f3599d9bc6d7c313caa891ddce4924055499b8b0a3de441a78080ce263cece45bfe967c5990a8c1d4e5acc2545e266fcda1080d07643818c33b753bbecc23e9b96bf009433e16703572dc7b6f5ee2c1dac225845d482836b7858f46eb9f7f48dc57e382e6ba92f5e2b31a11d51d3767f9218f0a793b3243e4987b69b60088372fdf48c7b652ff516213fac07e2c0d0143cb4f396df0d3fe9fbb44a99a622f1cd5b0ceb4fd159bf78e2aec5b175fdde3d29037c06fba6b92efa146d6eb1ba08f68555b4	f99be76ac60af2ecd59f4bbb4afca5ae3013a3606a92593553202d3ea4b86e20
authn:myConjurAccount	\\x47ab5b6a8e1245e82ed0fe7ee8a186d9d3baaaae3269faa3f9929d68c51f8f0879548152bbf8688e26c7c60476eef20325e43b65b60d5247f502928fd28a673b0b3e4db1f1972c118c31438b10c17826ae33b6b1d9ee1f982a0e5e5fbc08a6664c7f15b9b66ce718a4c9809c8c5cee5903341c1f757f7a4b332ca4e81ecc6f0c4fbf34716a8b46d33565e8a4886e342f4dc49f0aa8491af23b7863d9bae1e9449e8cdcb53be0f95278f9da5bc018af94c0b790b490862e4a1a90c90cd1c02c9e61b8060c2d6b951946b9fd8924234f14f4fd5ff4e082818cd9519dc69e3b3f7c1e8aa6fc67c01612a910fa5d08f222dbb65049ea83283b4b489f7a20970bef0abe7b67092221a0ee18a3a34b83d18336b613b7ff547b4670307cef6f3f52a24a95e72fe84a568d4ec2c29d1f73dd15d6ac948c869a4dc05bb9e45d431653835a03ca48b0d787d8355504b284611eaa9dd97e3022945c7a0cbb2d317d1810b436120a9942b7f6604e9c75c929171ee5a5703e24249180d4a0f97e48ddbdabb99abe64f8ff51dd445c9741ddc1e2d2e82ab8e98e432f482fea70fa930a73599ea5b4d7e61e0cdc18fc5ab2c9a26e4bf816af5caaf9e2e839fe41c628614f77019b0a807a9811c6af9074d3c6ae4acdf513cb870376024b404910afbbb2910ff2380836f4b7b8a5d8262a2872a1c58c86b3779f9a60498d00fe72ba6a57ff7d4a4232c3475248af4bef6857b3ae7eb7e8d822c07d9fad2c071f3afab22b32937b837c8c867769faaa5f244fe2e31093edf67f82079ceb013ac5109b1efb03764622202a2694fa0d57aa038a5bfa157b629ca8ea648048c27695e9f432aae9b39ce64101743409c611b6a4e8f9ba6c6744b1f0662b2baffa57650296fdeac80fe9c1eba5e39693ebc6f219002be0149698d1fe25853e3e35751f9ca7f53159f062489eca58c717824f7667ccdd9a7ecce4c2c418181b11281d1a5bef7250ddce9fa113fa58252fba447bead64ec0a28897c0b324a45c184ff3510fa9b978087ba7a1c85f8dbae29cee72d75081dc0c57c6fc655a464ddba8b538a8dcbb3a99bc01893ac2e5cd73e4921ebd8918604a518a433b057c8ff1d2be2dfab3058c84c7b54c5a1993dbf1cdc4e35a05b5fd115e60e6d9b40d7a1bd7769943395bb23c5606c1fcf0666829a982a26c5e45770061801b252ae0c53ae6eb8013c7dac7677038628236d141693a40da6339904dfd38f91522e396bf519557b0f688f56153488be096138589ed1084aa4d80dd895deacdc8b0224df168ae01258d3e4981b1ae3805de19b190102c5684dddb8fdcbe30527de8c778db9721c2fbda87bf39a8315f4bd68c2a433654c698f9e2e3107cdec02a2a045d8015b84383b9ac91e08ff638f170d701400fd1b124df41fed9c202814abb85a8be06b94b853f1f7e253cf4bf9bf8749965d6e5572e853efab25db1d3414ee100c9cb294c7b307ffe3f8b0cc8a54a05e257f930f019a35c4881549043f7cff3581cc7203917e7d859c7aad2d7e66bf47819f5b0508ffef2d45249147e411a742dea747dde1165e713ac888776dbc914c7a9e5ce76dfbd233c9038295b1e4139e8d4dc516cdd2e44c60e60c683a84b5f661a4ec0158a9f5ed720695690fc62d09bbafd0dd29b40abd0113629738d630b2dfd574fdd1470042a2273f7b5d3867ebd3ef3ca7c6fbd10214171094edb0882c541	da55ce54a90718c7502bca0f6ac20a579a20fa0ef837f43ddb693524b30cece8
\.


--
-- Name: authenticator_configs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.authenticator_configs_id_seq', 1, false);


--
-- Name: annotations annotations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_pkey PRIMARY KEY (resource_id, name);


--
-- Name: authenticator_configs authenticator_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_configs
    ADD CONSTRAINT authenticator_configs_pkey PRIMARY KEY (id);


--
-- Name: authenticator_configs authenticator_configs_resource_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_configs
    ADD CONSTRAINT authenticator_configs_resource_id_key UNIQUE (resource_id);


--
-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (role_id);


--
-- Name: host_factory_tokens host_factory_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.host_factory_tokens
    ADD CONSTRAINT host_factory_tokens_pkey PRIMARY KEY (token_sha256);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (resource_id, role_id, privilege);


--
-- Name: policy_versions policy_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policy_versions
    ADD CONSTRAINT policy_versions_pkey PRIMARY KEY (resource_id, version);


--
-- Name: resources resources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_pkey PRIMARY KEY (resource_id);


--
-- Name: resources_textsearch resources_textsearch_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources_textsearch
    ADD CONSTRAINT resources_textsearch_pkey PRIMARY KEY (resource_id);


--
-- Name: role_memberships role_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_memberships
    ADD CONSTRAINT role_memberships_pkey PRIMARY KEY (role_id, member_id, ownership);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (filename);


--
-- Name: secrets secrets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.secrets
    ADD CONSTRAINT secrets_pkey PRIMARY KEY (resource_id, version);


--
-- Name: slosilo_keystore slosilo_keystore_fingerprint_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.slosilo_keystore
    ADD CONSTRAINT slosilo_keystore_fingerprint_key UNIQUE (fingerprint);


--
-- Name: slosilo_keystore slosilo_keystore_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.slosilo_keystore
    ADD CONSTRAINT slosilo_keystore_pkey PRIMARY KEY (id);


--
-- Name: annotations_name_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX annotations_name_index ON public.annotations USING btree (name);


--
-- Name: policy_log_policy_id_version_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX policy_log_policy_id_version_index ON public.policy_log USING btree (policy_id, version);


--
-- Name: resources_account_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX resources_account_idx ON public.resources USING btree (public.account(resource_id));


--
-- Name: resources_account_kind_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX resources_account_kind_idx ON public.resources USING btree (public.account(resource_id), public.kind(resource_id));


--
-- Name: resources_kind_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX resources_kind_idx ON public.resources USING btree (public.kind(resource_id));


--
-- Name: resources_ts_index; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX resources_ts_index ON public.resources_textsearch USING gist (textsearch);


--
-- Name: role_memberships_member; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX role_memberships_member ON public.role_memberships USING btree (member_id);


--
-- Name: roles_account_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX roles_account_idx ON public.roles USING btree (public.account(role_id));


--
-- Name: roles_account_kind_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX roles_account_kind_idx ON public.roles USING btree (public.account(role_id), public.kind(role_id));


--
-- Name: roles_kind_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX roles_kind_idx ON public.roles USING btree (public.kind(role_id));


--
-- Name: secrets_account_kind_identifier_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX secrets_account_kind_identifier_idx ON public.secrets USING btree (public.account(resource_id), public.kind(resource_id), public.identifier(resource_id) text_pattern_ops);


--
-- Name: annotations annotation_update_textsearch; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER annotation_update_textsearch AFTER INSERT OR DELETE OR UPDATE ON public.annotations FOR EACH ROW EXECUTE PROCEDURE public.annotation_update_textsearch();


--
-- Name: resources delete_role_membership_of_owner; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER delete_role_membership_of_owner BEFORE DELETE ON public.resources FOR EACH ROW EXECUTE PROCEDURE public.delete_role_membership_of_owner_trigger();


--
-- Name: policy_versions finish_current; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER finish_current AFTER INSERT ON public.policy_versions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW WHEN ((new.finished_at IS NULL)) EXECUTE PROCEDURE public.policy_versions_finish();


--
-- Name: resources grant_role_membership_to_owner; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER grant_role_membership_to_owner BEFORE INSERT ON public.resources FOR EACH ROW EXECUTE PROCEDURE public.grant_role_membership_to_owner_trigger();


--
-- Name: policy_versions only_one_current; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER only_one_current BEFORE INSERT ON public.policy_versions FOR EACH ROW EXECUTE PROCEDURE public.policy_versions_finish();


--
-- Name: annotations policy_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log AFTER INSERT OR UPDATE ON public.annotations FOR EACH ROW WHEN ((new.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_annotations();


--
-- Name: permissions policy_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log AFTER INSERT OR UPDATE ON public.permissions FOR EACH ROW WHEN ((new.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_permissions();


--
-- Name: resources policy_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log AFTER INSERT OR UPDATE ON public.resources FOR EACH ROW WHEN ((new.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_resources();


--
-- Name: role_memberships policy_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log AFTER INSERT OR UPDATE ON public.role_memberships FOR EACH ROW WHEN ((new.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_role_memberships();


--
-- Name: roles policy_log; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log AFTER INSERT OR UPDATE ON public.roles FOR EACH ROW WHEN ((new.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_roles();


--
-- Name: annotations policy_log_d; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log_d AFTER DELETE ON public.annotations FOR EACH ROW WHEN ((old.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_annotations();


--
-- Name: permissions policy_log_d; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log_d AFTER DELETE ON public.permissions FOR EACH ROW WHEN ((old.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_permissions();


--
-- Name: resources policy_log_d; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log_d AFTER DELETE ON public.resources FOR EACH ROW WHEN ((old.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_resources();


--
-- Name: role_memberships policy_log_d; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log_d AFTER DELETE ON public.role_memberships FOR EACH ROW WHEN ((old.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_role_memberships();


--
-- Name: roles policy_log_d; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_log_d AFTER DELETE ON public.roles FOR EACH ROW WHEN ((old.policy_id IS NOT NULL)) EXECUTE PROCEDURE public.policy_log_roles();


--
-- Name: policy_versions policy_versions_version; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER policy_versions_version BEFORE INSERT ON public.policy_versions FOR EACH ROW EXECUTE PROCEDURE public.policy_versions_next_version();


--
-- Name: resources resource_update_textsearch; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER resource_update_textsearch AFTER INSERT OR UPDATE ON public.resources FOR EACH ROW EXECUTE PROCEDURE public.resource_update_textsearch();


--
-- Name: secrets secrets_version; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER secrets_version BEFORE INSERT ON public.secrets FOR EACH ROW EXECUTE PROCEDURE public.secrets_next_version();


--
-- Name: resources update_role_membership_of_owner; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_role_membership_of_owner BEFORE UPDATE ON public.resources FOR EACH ROW EXECUTE PROCEDURE public.update_role_membership_of_owner_trigger();


--
-- Name: annotations annotations_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: annotations annotations_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.annotations
    ADD CONSTRAINT annotations_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: authenticator_configs authenticator_configs_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.authenticator_configs
    ADD CONSTRAINT authenticator_configs_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: credentials credentials_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: host_factory_tokens host_factory_tokens_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.host_factory_tokens
    ADD CONSTRAINT host_factory_tokens_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: permissions permissions_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: permissions permissions_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: permissions permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: policy_log policy_log_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policy_log
    ADD CONSTRAINT policy_log_policy_id_fkey FOREIGN KEY (policy_id, version) REFERENCES public.policy_versions(resource_id, version) ON DELETE CASCADE;


--
-- Name: policy_versions policy_versions_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policy_versions
    ADD CONSTRAINT policy_versions_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: policy_versions policy_versions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.policy_versions
    ADD CONSTRAINT policy_versions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: resources resources_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: resources resources_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: resources_textsearch resources_textsearch_resource_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources_textsearch
    ADD CONSTRAINT resources_textsearch_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: role_memberships role_memberships_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_memberships
    ADD CONSTRAINT role_memberships_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: role_memberships role_memberships_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_memberships
    ADD CONSTRAINT role_memberships_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- Name: role_memberships role_memberships_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.role_memberships
    ADD CONSTRAINT role_memberships_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id) ON DELETE CASCADE;


--
-- Name: roles roles_policy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES public.resources(resource_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

