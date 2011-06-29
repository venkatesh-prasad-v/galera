/*
 * Copyright (C) 2008 Codership Oy <info@codership.com>
 *
 * $Id$
 */

#include <stdlib.h>

#include "gcs_node.h"

/*! Initialize node context */
void
gcs_node_init (gcs_node_t* const node,
               const char* const id,
               const char* const name,
               const char* const inc_addr,
               int const gcs_proto_ver,
               int const repl_proto_ver,
               int const appl_proto_ver)
{
    assert(strlen(id) > 0);
    assert(strlen(id) < sizeof(node->id));

    memset (node, 0, sizeof (gcs_node_t));
    strncpy ((char*)node->id, id, sizeof(node->id) - 1);
    node->status    = GCS_NODE_STATE_NON_PRIM;
    node->name      = strdup (name     ? name     : NODE_NO_NAME);
    node->inc_addr  = strdup (inc_addr ? inc_addr : NODE_NO_ADDR);
    gcs_defrag_init (&node->app);
    gcs_defrag_init (&node->oob);

    node->gcs_proto_ver  = gcs_proto_ver;
    node->repl_proto_ver = repl_proto_ver;
    node->appl_proto_ver = appl_proto_ver;
}

/*! Move data from one node object to another */
void
gcs_node_move (gcs_node_t* dst, gcs_node_t* src)
{
    if (dst->name)      free ((char*)dst->name);
    if (dst->inc_addr)  free ((char*)dst->inc_addr);

    if (dst->state_msg)
        gcs_state_msg_destroy ((gcs_state_msg_t*)dst->state_msg);

    memcpy (dst, src, sizeof (gcs_node_t));
    gcs_defrag_forget (&src->app);
    gcs_defrag_forget (&src->oob);
    src->name      = NULL;
    src->inc_addr  = NULL;
    src->state_msg = NULL;
}

/*! Mark node's buffers as reset (local node only) */
void
gcs_node_reset_local (gcs_node_t* node)
{
    gcs_defrag_reset (&node->app);
    gcs_defrag_reset (&node->oob);
}

/*! Reset node's receive buffers */
void
gcs_node_reset (gcs_node_t* node) {
    gcs_defrag_free (&node->app);
    gcs_defrag_free (&node->oob);
    gcs_node_reset_local (node);
}

/*! Deallocate resources associated with the node object */
void
gcs_node_free (gcs_node_t* node)
{
    gcs_node_reset (node);

    if (node->name) {
        free ((char*)node->name);     // was strdup'ed
        node->name = NULL;
    }

    if (node->inc_addr) {
        free ((char*)node->inc_addr); // was strdup'ed
        node->inc_addr = NULL;
    }

    if (node->state_msg) {
        gcs_state_msg_destroy ((gcs_state_msg_t*)node->state_msg);
        node->state_msg = NULL;
    }
}

/*! Record state message from the node */
void
gcs_node_record_state (gcs_node_t* node, gcs_state_msg_t* state_msg)
{
    if (node->state_msg) {
        gcs_state_msg_destroy ((gcs_state_msg_t*)node->state_msg);
    }
    node->state_msg = state_msg;

    // copy relevant stuff from state msg into node
    node->status = gcs_state_msg_current_state (state_msg);

    gcs_state_msg_get_proto_ver (state_msg,
                                 &node->gcs_proto_ver,
                                 &node->repl_proto_ver,
                                 &node->appl_proto_ver);

    if (node->name) free ((char*)node->name);
    node->name = strdup (gcs_state_msg_name (state_msg));

    if (node->inc_addr) free ((char*)node->inc_addr);
    node->inc_addr = strdup (gcs_state_msg_inc_addr (state_msg));
}

/*! Update node status according to quorum decisions */
void
gcs_node_update_status (gcs_node_t* node, const gcs_state_quorum_t* quorum)
{
    if (quorum->primary) {
        const gu_uuid_t* node_group_uuid   = gcs_state_msg_group_uuid (
            node->state_msg);
        const gu_uuid_t* quorum_group_uuid = &quorum->group_uuid;

        // TODO: what to do when quorum.proto is not supported by this node?

        if (!gu_uuid_compare (node_group_uuid, quorum_group_uuid)) {
            // node was a part of this group
            gcs_seqno_t node_act_id = gcs_state_msg_act_id (node->state_msg);

             if (node_act_id == quorum->act_id) {
                const gcs_node_state_t last_prim_state =
                    gcs_state_msg_prim_state (node->state_msg);

                if (GCS_NODE_STATE_NON_PRIM == last_prim_state) {
                    // the node just joined, but already is up to date:
                    node->status = GCS_NODE_STATE_JOINED;
                    gu_debug ("#281 Setting %s state to %s",
                              node->name, gcs_node_state_to_str(node->status));
                }
                else  {
                    // Keep node state from the previous primary comp.
                    node->status = last_prim_state;
                    gu_debug ("#281,#298 Carry over last prim state for %s: %s",
                              node->name, gcs_node_state_to_str(node->status));
                }
            }
            else {
                // gap in sequence numbers, needs a snapshot, demote status
                node->status = GCS_NODE_STATE_PRIM;
            }
        }
        else {
            // node joins completely different group, clear all status
            node->status = GCS_NODE_STATE_PRIM;
        }
    }
    else {
        /* Probably don't want to change anything here, quorum was a failure
         * anyway. This could be due to this being transient component, lacking
         * joined nodes from the configuraiton. May be next component will be
         * better.
         *
         * UPDATE (28.06.2011): as #477 shows, we need some consistency here:
         */
        node->status = GCS_NODE_STATE_NON_PRIM;
    }
}
