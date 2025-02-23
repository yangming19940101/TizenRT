/****************************************************************************
 *
 * Copyright 2023 Samsung Electronics All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 * either express or implied. See the License for the specific
 * language governing permissions and limitations under the License.
 *
 ****************************************************************************/
/****************************************************************************
 * arch/arm/src/armv7-a/arm_reprioritizertr.c
 *
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.  The
 * ASF licenses this file to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations
 * under the License.
 *
 ****************************************************************************/

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <tinyara/config.h>

#include <stdint.h>
#include <stdbool.h>
#include <sched.h>
#include <assert.h>
#include <debug.h>
#include <tinyara/arch.h>
#include <tinyara/sched.h>

#include "sched/sched.h"
#include "group/group.h"
#include "arm_internal.h"

/****************************************************************************
 * Public Functions
 ****************************************************************************/

/****************************************************************************
 * Name: up_reprioritize_rtr
 *
 * Description:
 *   Called when the priority of a running or
 *   ready-to-run task changes and the reprioritization will
 *   cause a context switch.  Two cases:
 *
 *   1) The priority of the currently running task drops and the next
 *      task in the ready to run list has priority.
 *   2) An idle, ready to run task's priority has been raised above the
 *      priority of the current, running task and it now has the priority.
 *
 * Input Parameters:
 *   tcb: The TCB of the task that has been reprioritized
 *   priority: The new task priority
 *
 ****************************************************************************/

void up_reprioritize_rtr(struct tcb_s *tcb, uint8_t priority)
{
  /* Verify that the caller is sane */

  if (tcb->task_state < FIRST_READY_TO_RUN_STATE ||
      tcb->task_state > LAST_READY_TO_RUN_STATE
#if SCHED_PRIORITY_MIN > 0
      || priority < SCHED_PRIORITY_MIN
#endif
#if SCHED_PRIORITY_MAX < UINT8_MAX
      || priority > SCHED_PRIORITY_MAX
#endif
    )
    {
       DEBUGPANIC();
    }
  else
    {
      struct tcb_s *rtcb = this_task();
      bool switch_needed;

      svdbg("TCB=%p PRI=%d\n", tcb, priority);

      /* Remove the tcb task from the ready-to-run list.
       * sched_remove_readytorun will return true if we just
       * remove the head of the ready to run list.
       */

      switch_needed = sched_removereadytorun(tcb);

      /* Setup up the new task priority */

      tcb->sched_priority = (uint8_t)priority;

      /* Return the task to the specified blocked task list.
       * sched_add_readytorun will return true if the task was
       * added to the new list.  We will need to perform a context
       * switch only if the EXCLUSIVE or of the two calls is non-zero
       * (i.e., one and only one the calls changes the head of the
       * ready-to-run list).
       */

      switch_needed ^= sched_addreadytorun(tcb);

      /* Now, perform the context switch if one is needed */

      if (switch_needed)
        {
          /* If we are going to do a context switch, then now is the right
           * time to add any pending tasks back into the ready-to-run list.
           */

          if (g_pendingtasks.head)
            {
              sched_mergepending();
            }

          /* Update scheduler parameters */

          //sched_suspendscheduler(rtcb);

          /* Are we in an interrupt handler? */

          if (CURRENT_REGS)
            {
              /* Yes, then we have to do things differently.
               * Just copy the CURRENT_REGS into the OLD rtcb.
               */

               arm_savestate(rtcb->xcp.regs);

              /* Restore the exception context of the rtcb at the (new) head
               * of the ready-to-run task list.
               */

              rtcb = this_task();

	      /* Restore rtcb data for context switching */

              up_restoretask(rtcb);

              /* Update scheduler parameters */

              //sched_resume_scheduler(rtcb);

              /* Then switch contexts.  Any necessary address environment
               * changes will be made when the interrupt returns.
               */

              arm_restorestate(rtcb->xcp.regs);
            }

          /* No, then we will need to perform the user context switch */

          else
            {
              struct tcb_s *nexttcb = this_task();

              /* Update scheduler parameters */

              //sched_resume_scheduler(nexttcb);

              /* Switch context to the context of the task at the head of the
               * ready to run list.
               */

              arm_switchcontext(&rtcb->xcp.regs, nexttcb->xcp.regs);

              /* arm_switchcontext forces a context switch to the task at the
               * head of the ready-to-run list.  It does not 'return' in the
               * normal sense.  When it does return, it is because the
               * blocked task is again ready to run and has execution
               * priority.
               */
            }
        }
    }
}
