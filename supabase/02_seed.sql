-- Enable RLS on all tables except templates
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE center_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_list_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_instance_managers ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_instance_assignees ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE list_signoffs ENABLE ROW LEVEL SECURITY;

-- Helper function: check if user has role in center
CREATE OR REPLACE FUNCTION has_center_role(p_center_id uuid, p_role membership_role)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM center_memberships
    WHERE center_id = p_center_id
      AND user_id = auth.uid()
      AND role = p_role
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: check if user has any of roles in center
CREATE OR REPLACE FUNCTION has_any_center_role(p_center_id uuid, p_roles membership_role[])
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM center_memberships
    WHERE center_id = p_center_id
      AND user_id = auth.uid()
      AND role = ANY(p_roles)
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: check if user is owner or director
CREATE OR REPLACE FUNCTION is_owner_or_director(p_center_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN has_any_center_role(p_center_id, ARRAY['owner', 'director']::membership_role[]);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: check if user manages list instance
CREATE OR REPLACE FUNCTION manages_list_instance(p_list_instance_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM list_instance_managers
    WHERE list_instance_id = p_list_instance_id
      AND user_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function: check if staff can view list instance
CREATE OR REPLACE FUNCTION staff_can_view_instance(p_list_instance_id uuid)
RETURNS boolean AS $$
DECLARE
  v_center_id uuid;
  v_has_assignees boolean;
BEGIN
  SELECT center_id INTO v_center_id FROM list_instances WHERE id = p_list_instance_id;
  
  IF NOT has_center_role(v_center_id, 'staff') THEN
    RETURN false;
  END IF;
  
  SELECT EXISTS (
    SELECT 1 FROM list_instance_assignees WHERE list_instance_id = p_list_instance_id
  ) INTO v_has_assignees;
  
  IF NOT v_has_assignees THEN
    RETURN true;
  END IF;
  
  RETURN EXISTS (
    SELECT 1 FROM list_instance_assignees
    WHERE list_instance_id = p_list_instance_id
      AND (
        (assignee_type = 'user' AND user_id = auth.uid())
        OR (assignee_type = 'role' AND role = 'staff')
      )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- GROUPS
CREATE POLICY groups_select ON groups FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM centers c
      INNER JOIN center_memberships cm ON c.id = cm.center_id
      WHERE c.group_id = groups.id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY groups_insert ON groups FOR INSERT
  WITH CHECK (false);

CREATE POLICY groups_update ON groups FOR UPDATE
  USING (false);

CREATE POLICY groups_delete ON groups FOR DELETE
  USING (false);

-- CENTERS
CREATE POLICY centers_select ON centers FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM center_memberships
      WHERE center_id = centers.id
        AND user_id = auth.uid()
        AND status = 'active'
    )
  );

CREATE POLICY centers_insert ON centers FOR INSERT
  WITH CHECK (false);

CREATE POLICY centers_update ON centers FOR UPDATE
  USING (is_owner_or_director(id));

CREATE POLICY centers_delete ON centers FOR DELETE
  USING (is_owner_or_director(id));

-- ROOMS
CREATE POLICY rooms_select ON rooms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM center_memberships
      WHERE center_id = rooms.center_id
        AND user_id = auth.uid()
        AND status = 'active'
    )
  );

CREATE POLICY rooms_insert ON rooms FOR INSERT
  WITH CHECK (is_owner_or_director(center_id));

CREATE POLICY rooms_update ON rooms FOR UPDATE
  USING (is_owner_or_director(center_id));

CREATE POLICY rooms_delete ON rooms FOR DELETE
  USING (is_owner_or_director(center_id));

-- CENTER_MEMBERSHIPS
CREATE POLICY center_memberships_select ON center_memberships FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM center_memberships cm
      WHERE cm.center_id = center_memberships.center_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY center_memberships_insert ON center_memberships FOR INSERT
  WITH CHECK (is_owner_or_director(center_id));

CREATE POLICY center_memberships_update ON center_memberships FOR UPDATE
  USING (is_owner_or_director(center_id));

CREATE POLICY center_memberships_delete ON center_memberships FOR DELETE
  USING (is_owner_or_director(center_id));

-- TASK_LISTS
CREATE POLICY task_lists_select ON task_lists FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM center_memberships
      WHERE center_id = task_lists.center_id
        AND user_id = auth.uid()
        AND status = 'active'
    )
  );

CREATE POLICY task_lists_insert ON task_lists FOR INSERT
  WITH CHECK (is_owner_or_director(center_id));

CREATE POLICY task_lists_update ON task_lists FOR UPDATE
  USING (is_owner_or_director(center_id));

CREATE POLICY task_lists_delete ON task_lists FOR DELETE
  USING (is_owner_or_director(center_id));

-- TASK_LIST_TASKS
CREATE POLICY task_list_tasks_select ON task_list_tasks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM task_lists tl
      INNER JOIN center_memberships cm ON tl.center_id = cm.center_id
      WHERE tl.id = task_list_tasks.task_list_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY task_list_tasks_insert ON task_list_tasks FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM task_lists tl
      WHERE tl.id = task_list_id
        AND is_owner_or_director(tl.center_id)
    )
  );

CREATE POLICY task_list_tasks_update ON task_list_tasks FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM task_lists tl
      WHERE tl.id = task_list_id
        AND is_owner_or_director(tl.center_id)
    )
  );

CREATE POLICY task_list_tasks_delete ON task_list_tasks FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM task_lists tl
      WHERE tl.id = task_list_id
        AND is_owner_or_director(tl.center_id)
    )
  );

-- LIST_INSTANCES
CREATE POLICY list_instances_select ON list_instances FOR SELECT
  USING (
    is_owner_or_director(center_id)
    OR manages_list_instance(id)
    OR staff_can_view_instance(id)
  );

CREATE POLICY list_instances_insert ON list_instances FOR INSERT
  WITH CHECK (is_owner_or_director(center_id));

CREATE POLICY list_instances_update ON list_instances FOR UPDATE
  USING (is_owner_or_director(center_id));

CREATE POLICY list_instances_delete ON list_instances FOR DELETE
  USING (is_owner_or_director(center_id));

-- LIST_INSTANCE_MANAGERS
CREATE POLICY list_instance_managers_select ON list_instance_managers FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      INNER JOIN center_memberships cm ON li.center_id = cm.center_id
      WHERE li.id = list_instance_managers.list_instance_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY list_instance_managers_insert ON list_instance_managers FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

CREATE POLICY list_instance_managers_update ON list_instance_managers FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

CREATE POLICY list_instance_managers_delete ON list_instance_managers FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

-- LIST_INSTANCE_ASSIGNEES
CREATE POLICY list_instance_assignees_select ON list_instance_assignees FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      INNER JOIN center_memberships cm ON li.center_id = cm.center_id
      WHERE li.id = list_instance_assignees.list_instance_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
    )
  );

CREATE POLICY list_instance_assignees_insert ON list_instance_assignees FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

CREATE POLICY list_instance_assignees_update ON list_instance_assignees FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

CREATE POLICY list_instance_assignees_delete ON list_instance_assignees FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

-- TASK_OVERRIDES
CREATE POLICY task_overrides_select ON task_overrides FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = task_overrides.list_instance_id
        AND (
          is_owner_or_director(li.center_id)
          OR manages_list_instance(li.id)
          OR staff_can_view_instance(li.id)
        )
    )
  );

CREATE POLICY task_overrides_insert ON task_overrides FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

CREATE POLICY task_overrides_update ON task_overrides FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND (
          is_owner_or_director(li.center_id)
          OR manages_list_instance(li.id)
        )
    )
  );

CREATE POLICY task_overrides_delete ON task_overrides FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND is_owner_or_director(li.center_id)
    )
  );

-- TASK_COMPLETIONS
CREATE POLICY task_completions_select ON task_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = task_completions.list_instance_id
        AND (
          is_owner_or_director(li.center_id)
          OR manages_list_instance(li.id)
          OR staff_can_view_instance(li.id)
        )
    )
  );

CREATE POLICY task_completions_insert ON task_completions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_instance_id
        AND (
          is_owner_or_director(li.center_id)
          OR manages_list_instance(li.id)
          OR staff_can_view_instance(li.id)
        )
    )
  );

CREATE POLICY task_completions_update ON task_completions FOR UPDATE
  USING (false);

CREATE POLICY task_completions_delete ON task_completions FOR DELETE
  USING (false);

-- LIST_SIGNOFFS
CREATE POLICY list_signoffs_select ON list_signoffs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM list_instances li
      WHERE li.id = list_signoffs.list_instance_id
        AND (
          is_owner_or_director(li.center_id)
          OR manages_list_instance(li.id)
          OR staff_can_view_instance(li.id)
        )
    )
  );

CREATE POLICY list_signoffs_insert ON list_signoffs FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM list_instances li
      INNER JOIN center_memberships cm ON li.center_id = cm.center_id
      WHERE li.id = list_instance_id
        AND cm.user_id = auth.uid()
        AND cm.status = 'active'
        AND cm.role IN ('owner', 'director', 'manager')
        AND (
          is_owner_or_director(li.center_id)
          OR manages_list_instance(li.id)
        )
    )
  );

CREATE POLICY list_signoffs_update ON list_signoffs FOR UPDATE
  USING (false);

CREATE POLICY list_signoffs_delete ON list_signoffs FOR DELETE
  USING (false);
