SET search_path TO linhagem;

-- Mantém o grafo acíclico. O lock serializa inserções concorrentes: sem ele, A->B e B->A
-- em transações simultâneas passariam, porque nenhuma enxerga a aresta da outra.
CREATE FUNCTION fn_bloquear_ciclo() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_caminho text;
BEGIN
    IF NEW.vigente_ate IS NOT NULL THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('linhagem.dependencia'));

    WITH RECURSIVE alcance (id, caminho) AS (
        SELECT NEW.destino_id, ARRAY[NEW.destino_id]
        UNION ALL
        SELECT d.destino_id, a.caminho || d.destino_id
        FROM linhagem.dependencia d
        JOIN alcance a ON d.origem_id = a.id
        WHERE d.vigente_ate IS NULL
          AND d.id IS DISTINCT FROM NEW.id
          AND d.destino_id <> ALL (a.caminho)
    )
    SELECT string_agg(at.codigo, ' -> ' ORDER BY u.ord)
    INTO v_caminho
    FROM (SELECT caminho FROM alcance WHERE id = NEW.origem_id LIMIT 1) c
    CROSS JOIN LATERAL unnest(c.caminho) WITH ORDINALITY AS u (ativo_id, ord)
    JOIN linhagem.ativo at ON at.id = u.ativo_id;

    IF v_caminho IS NOT NULL THEN
        RAISE EXCEPTION 'Esta dependência fecharia um ciclo no grafo: %', v_caminho
            USING ERRCODE = 'LN001';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_dependencia_sem_ciclo
    BEFORE INSERT OR UPDATE OF origem_id, destino_id, vigente_ate ON dependencia
    FOR EACH ROW EXECUTE FUNCTION fn_bloquear_ciclo();

CREATE FUNCTION fn_auditar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_antes  jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
    v_depois jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
BEGIN
    INSERT INTO linhagem.auditoria (tabela, registro_id, operacao, antes, depois, usuario)
    VALUES (TG_TABLE_NAME,
            COALESCE(v_depois ->> 'id', v_antes ->> 'id'),
            TG_OP, v_antes, v_depois,
            COALESCE(NULLIF(current_setting('app.usuario', true), ''), session_user));
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON ativo
    FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON processo
    FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON dependencia
    FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON regra
    FOR EACH ROW EXECUTE FUNCTION fn_auditar();
CREATE TRIGGER trg_auditar AFTER INSERT OR UPDATE OR DELETE ON atributo
    FOR EACH ROW EXECUTE FUNCTION fn_auditar();

CREATE FUNCTION fn_tocar_atualizado() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.atualizado_em := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tocar BEFORE UPDATE ON ativo
    FOR EACH ROW EXECUTE FUNCTION fn_tocar_atualizado();
